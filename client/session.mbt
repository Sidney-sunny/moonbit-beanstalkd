///|
/// Local state failures are distinct from complete server status replies.
pub(all) enum ClientError {
  Busy
  Closed
  Protocol(@protocol.ProtocolError)
  UnexpectedReply
  UnsolicitedData
} derive(Eq, @debug.Debug)

///|
pub extend ClientError with Eq::{equal, not_equal}

///|
pub extend ClientError with @debug.Debug::{to_repr}

///|
/// Transport-independent one-command-at-a-time Beanstalkd session.
pub struct Session {
  priv decoder : @protocol.Decoder
  priv mut pending : @protocol.Command?
  priv mut usable : Bool
  priv mut used_tube : String
  priv mut watching : UInt64
}

///|
pub fn Session::new(
  max_header~ : Int32 = 1024,
  max_body~ : Int32 = 1048576,
  max_buffer~ : Int32 = 2097152,
) -> Session {
  {
    decoder: @protocol.Decoder::new(max_header~, max_body~, max_buffer~),
    pending: None,
    usable: true,
    used_tube: "default",
    watching: 1UL,
  }
}

///|
pub fn Session::is_usable(self : Session) -> Bool {
  self.usable
}

///|
pub fn Session::is_busy(self : Session) -> Bool {
  self.pending is Some(_)
}

///|
pub fn Session::used_tube(self : Session) -> String {
  self.used_tube
}

///|
pub fn Session::watching_count(self : Session) -> UInt64 {
  self.watching
}

///|
/// Validate and encode locally before marking a request in flight.
pub fn Session::begin(
  self : Session,
  command : @protocol.Command,
) -> Result[Bytes, ClientError] {
  if !self.usable {
    return Err(Closed)
  }
  if self.pending is Some(_) {
    return Err(Busy)
  }
  // Surface invalid local limits before returning bytes a transport may send.
  match self.decoder.feed(b"") {
    Err(error) => {
      self.invalidate()
      return Err(Protocol(error))
    }
    Ok(_) => ()
  }
  match @protocol.encode(command) {
    Err(error) => Err(Protocol(error))
    Ok(bytes) => {
      self.pending = Some(command)
      Ok(bytes)
    }
  }
}

///|
fn accepts(command : @protocol.Command, reply : @protocol.Reply) -> Bool {
  match (command, reply) {
    (Use(tube), Using(actual)) => tube == actual
    (ListTubeUsed, Using(_)) => true
    (Watch(_), Watching(count)) | (Ignore(_), Watching(count)) => count > 0UL
    (Put(_, _, _, _), Inserted(_) | Buried(_)) => true
    (ReserveWithTimeout(_), Reserved(_, _)) => true
    (Peek(expected_id), Found(actual_id, _)) => expected_id == actual_id
    (PeekReady | PeekDelayed | PeekBuried, Found(_, _)) => true
    (Kick(bound), Kicked(count)) => count <= bound.to_uint64()
    (Stats | StatsJob(_) | StatsTube(_) | ListTubes | ListTubesWatched, Ok(_)) =>
      true
    (_, Status(status)) =>
      match (command, status) {
        (_, OutOfMemory | InternalError | BadFormat | UnknownCommand) => true
        (Put(_, _, _, _), JobTooBig | Draining | ExpectedCrlf) => true
        (ReserveWithTimeout(_), TimedOut | DeadlineSoon) => true
        (Ignore(_), NotIgnored) => true
        (Delete(_), Deleted | NotFound) => true
        (Release(_, _, _), Released | Buried | NotFound) => true
        (Bury(_, _), Buried | NotFound) => true
        (KickJob(_), Kicked | NotFound) => true
        (Touch(_), Touched | NotFound) => true
        (
          Peek(_)
          | PeekReady
          | PeekDelayed
          | PeekBuried
          | StatsJob(_)
          | StatsTube(_),
          NotFound,
        ) => true
        _ => false
      }
    _ => false
  }
}

///|
/// Return a complete, command-matched reply or request more bytes with None.
/// Malformed or unsolicited data permanently invalidates the session.
pub fn Session::feed(
  self : Session,
  bytes : Bytes,
) -> Result[@protocol.Reply?, ClientError] {
  if !self.usable {
    return Err(Closed)
  }
  let command = match self.pending {
    Some(command) => command
    None => {
      self.invalidate()
      return Err(UnsolicitedData)
    }
  }
  match self.decoder.feed(bytes) {
    Err(error) => {
      self.invalidate()
      return Err(Protocol(error))
    }
    Ok(_) => ()
  }
  match self.decoder.take() {
    Err(error) => {
      self.invalidate()
      Err(Protocol(error))
    }
    Ok(None) => Ok(None)
    Ok(Some(reply)) => {
      if !accepts(command, reply) {
        self.invalidate()
        return Err(UnexpectedReply)
      }
      if self.decoder.buffered_bytes() != 0 {
        self.invalidate()
        return Err(UnsolicitedData)
      }
      match reply {
        Using(tube) => self.used_tube = tube
        Watching(count) => self.watching = count
        _ => ()
      }
      self.pending = None
      Ok(Some(reply))
    }
  }
}

///|
/// Invalidate on transport timeout, cancellation, EOF, or uncertain writes.
pub fn Session::invalidate(self : Session) -> Unit {
  self.usable = false
  self.pending = None
}

///|
/// Report an incomplete exchange at EOF, even when no reply bytes arrived.
pub fn Session::finish(self : Session) -> Result[Unit, ClientError] {
  let was_busy = self.is_busy()
  self.invalidate()
  match self.decoder.finish() {
    Err(error) => Err(Protocol(error))
    Ok(_) => if was_busy { Err(Protocol(Truncated)) } else { Ok(()) }
  }
}
