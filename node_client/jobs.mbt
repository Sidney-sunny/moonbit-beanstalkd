///|
/// A reserved or peeked job. Bodies stay opaque bytes; IDs retain all 64 bits.
pub(all) struct Job {
  id : UInt64
  body : Bytes
} derive(Eq, @debug.Debug)

///|
pub extend Job with Eq::{equal, not_equal}

///|
pub extend Job with @debug.Debug::{to_repr}

///|
/// Both outcomes mean the server accepted the new job; a buried job is not ready.
pub(all) enum PutOutcome {
  Inserted(UInt64)
  Buried(UInt64)
} derive(Eq, @debug.Debug)

///|
pub extend PutOutcome with Eq::{equal, not_equal}

///|
pub extend PutOutcome with @debug.Debug::{to_repr}

///|
pub(all) enum ReserveOutcome {
  Reserved(Job)
  TimedOut
  DeadlineSoon
} derive(Eq, @debug.Debug)

///|
pub extend ReserveOutcome with Eq::{equal, not_equal}

///|
pub extend ReserveOutcome with @debug.Debug::{to_repr}

///|
pub(all) enum ReleaseOutcome {
  Released
  Buried
  NotFound
} derive(Eq, @debug.Debug)

///|
pub extend ReleaseOutcome with Eq::{equal, not_equal}

///|
pub extend ReleaseOutcome with @debug.Debug::{to_repr}

///|
/// Complete server rejections preserve their exact status. Transport failures
/// remain TransportError; none of these helpers reconnects or replays a command.
pub suberror OperationError {
  ServerRejected(@protocol.ServerStatus)
  InvalidDocument(@protocol.ProtocolError)
  UnexpectedResponse
} derive(@debug.Debug)

///|
pub extend OperationError with @debug.Debug::{to_repr}

///|
fn[T] reject_operation(reply : @protocol.Reply) -> T raise OperationError {
  match reply {
    Status(status) => raise ServerRejected(status)
    _ => raise UnexpectedResponse
  }
}

///|
pub async fn Client::put(
  self : Client,
  body : Bytes,
  priority~ : UInt32 = 0U,
  delay~ : UInt32 = 0U,
  ttr~ : UInt32 = 60U,
  timeout_ms~ : Int32 = 5000,
) -> PutOutcome {
  match self.execute(@protocol.Put(priority, delay, ttr, body), timeout_ms~) {
    Inserted(id) => PutOutcome::Inserted(id)
    Buried(id) => PutOutcome::Buried(id)
    reply => reject_operation(reply)
  }
}

///|
/// Server timeout and TTR safety-margin replies are normal typed outcomes.
/// timeout_ms is the transport deadline and should exceed a blocking reserve.
pub async fn Client::reserve(
  self : Client,
  timeout_seconds~ : UInt32 = 0U,
  timeout_ms~ : Int32 = 5000,
) -> ReserveOutcome {
  match
    self.execute(@protocol.ReserveWithTimeout(timeout_seconds), timeout_ms~) {
    Reserved(id, body) => ReserveOutcome::Reserved({ id, body, })
    Status(TimedOut) => ReserveOutcome::TimedOut
    Status(DeadlineSoon) => ReserveOutcome::DeadlineSoon
    reply => reject_operation(reply)
  }
}

///|
/// Return false for NOT_FOUND, true for a deleted job.
pub async fn Client::delete(
  self : Client,
  id : UInt64,
  timeout_ms~ : Int32 = 5000,
) -> Bool {
  match self.execute(@protocol.Delete(id), timeout_ms~) {
    Status(Deleted) => true
    Status(NotFound) => false
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::release(
  self : Client,
  id : UInt64,
  priority~ : UInt32 = 0U,
  delay~ : UInt32 = 0U,
  timeout_ms~ : Int32 = 5000,
) -> ReleaseOutcome {
  match self.execute(@protocol.Release(id, priority, delay), timeout_ms~) {
    Status(Released) => ReleaseOutcome::Released
    Status(Buried) => ReleaseOutcome::Buried
    Status(NotFound) => ReleaseOutcome::NotFound
    reply => reject_operation(reply)
  }
}

///|
/// Return false when the job is absent or not reserved by this connection.
pub async fn Client::bury(
  self : Client,
  id : UInt64,
  priority~ : UInt32 = 0U,
  timeout_ms~ : Int32 = 5000,
) -> Bool {
  match self.execute(@protocol.Bury(id, priority), timeout_ms~) {
    Status(Buried) => true
    Status(NotFound) => false
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::kick(
  self : Client,
  bound : UInt32,
  timeout_ms~ : Int32 = 5000,
) -> UInt64 {
  match self.execute(@protocol.Kick(bound), timeout_ms~) {
    Kicked(count) => count
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::kick_job(
  self : Client,
  id : UInt64,
  timeout_ms~ : Int32 = 5000,
) -> Bool {
  match self.execute(@protocol.KickJob(id), timeout_ms~) {
    Status(Kicked) => true
    Status(NotFound) => false
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::touch(
  self : Client,
  id : UInt64,
  timeout_ms~ : Int32 = 5000,
) -> Bool {
  match self.execute(@protocol.Touch(id), timeout_ms~) {
    Status(Touched) => true
    Status(NotFound) => false
    reply => reject_operation(reply)
  }
}
