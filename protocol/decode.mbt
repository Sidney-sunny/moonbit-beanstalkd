///|
priv enum BodyHeader {
  Reserved(UInt64, Int32)
  Found(UInt64, Int32)
  Ok(Int32)
}

///|
priv enum Header {
  Complete(Reply)
  Body(BodyHeader)
}

///|
/// A bounded incremental decoder. Call take after feed until it returns None.
/// Limits count header content excluding CRLF, body bytes, and all buffered
/// bytes respectively. Errors are sticky and require connection invalidation.
pub struct Decoder {
  priv mut data : Array[Byte]
  priv mut start : Int32
  priv mut scan : Int32
  priv mut pending : BodyHeader?
  priv mut failure : ProtocolError?
  priv max_header : Int32
  priv max_body : Int32
  priv max_buffer : Int32
}

///|
pub fn Decoder::new(
  max_header~ : Int32 = 1024,
  max_body~ : Int32 = 1048576,
  max_buffer~ : Int32 = 2097152,
) -> Decoder {
  {
    data: [],
    start: 0,
    scan: 0,
    pending: None,
    failure: if max_header <= 0 || max_body < 0 || max_buffer <= 0 {
      Some(InvalidLimits)
    } else {
      None
    },
    max_header,
    max_body,
    max_buffer,
  }
}

///|
pub fn Decoder::buffered_bytes(self : Decoder) -> Int32 {
  self.data.length() - self.start
}

///|
pub fn Decoder::feed(
  self : Decoder,
  bytes : Bytes,
) -> Result[Unit, ProtocolError] {
  if self.failure is Some(error) {
    return Err(error)
  }
  let retained = self.buffered_bytes()
  if bytes.length() > self.max_buffer - retained {
    let error = BufferTooLarge(self.max_buffer)
    self.failure = Some(error)
    return Err(error)
  }
  if self.start > 0 {
    self.data = self.data[self.start:].to_owned()
    self.scan = self.scan - self.start
    self.start = 0
  }
  self.data.push_iter(bytes.iter())
  Ok(())
}

///|
fn parse_u64(value : String) -> Result[UInt64, ProtocolError] {
  let bytes = @utf8.encode(value)
  if bytes.is_empty() {
    return Err(MalformedHeader(value))
  }
  let mut number = 0UL
  for byte in bytes {
    if byte < b'0' || byte > b'9' {
      return Err(MalformedHeader(value))
    }
    let digit = (byte.to_int() - 48).to_uint64()
    if number > (18446744073709551615UL - digit) / 10UL {
      return Err(IntegerOverflow(value))
    }
    number = number * 10UL + digit
  }
  Ok(number)
}

///|
fn parse_header(
  line : String,
  max_body : Int32,
) -> Result[Header, ProtocolError] {
  let fields = line.split(" ").map(fn(s) { s.to_owned() }).collect()
  match fields {
    ["INSERTED", id] | ["BURIED", id] | ["WATCHING", id] | ["KICKED", id] =>
      match parse_u64(id) {
        Err(error) => Err(error)
        Ok(number) => {
          let reply = match fields[0] {
            "INSERTED" => Reply::Inserted(number)
            "BURIED" => Reply::Buried(number)
            "WATCHING" => Reply::Watching(number)
            _ => Reply::Kicked(number)
          }
          Ok(Complete(reply))
        }
      }
    ["USING", tube] =>
      if valid_tube(tube) {
        Ok(Complete(Using(tube)))
      } else {
        Err(MalformedHeader(line))
      }
    ["RESERVED", id, length] | ["FOUND", id, length] =>
      match (parse_u64(id), parse_u64(length)) {
        (Ok(id), Ok(length)) => {
          if length > max_body.to_uint64() {
            return Err(BodyTooLarge(length))
          }
          if fields[0] == "RESERVED" {
            Ok(Body(Reserved(id, length.to_int())))
          } else {
            Ok(Body(Found(id, length.to_int())))
          }
        }
        (Err(error), _) | (_, Err(error)) => Err(error)
      }
    ["OK", length] =>
      match parse_u64(length) {
        Err(error) => Err(error)
        Ok(length) =>
          if length > max_body.to_uint64() {
            Err(BodyTooLarge(length))
          } else {
            Ok(Body(Ok(length.to_int())))
          }
      }
    [word] => {
      let status = match word {
        "DELETED" => Deleted
        "RELEASED" => Released
        "BURIED" => Buried
        "KICKED" => Kicked
        "TOUCHED" => Touched
        "TIMED_OUT" => TimedOut
        "DEADLINE_SOON" => DeadlineSoon
        "NOT_FOUND" => NotFound
        "NOT_IGNORED" => NotIgnored
        "JOB_TOO_BIG" => JobTooBig
        "DRAINING" => Draining
        "EXPECTED_CRLF" => ExpectedCrlf
        "OUT_OF_MEMORY" => OutOfMemory
        "INTERNAL_ERROR" => InternalError
        "BAD_FORMAT" => BadFormat
        "UNKNOWN_COMMAND" => UnknownCommand
        _ => return Err(MalformedHeader(line))
      }
      Ok(Complete(Status(status)))
    }
    _ => Err(MalformedHeader(line))
  }
}

///|
fn Decoder::fail(
  self : Decoder,
  error : ProtocolError,
) -> Result[Reply?, ProtocolError] {
  self.failure = Some(error)
  Err(error)
}

///|
/// Return one reply, or None if the current frame needs more bytes. Never
/// interprets a job body's bytes as text or permits uncertain resynchronization.
pub fn Decoder::take(self : Decoder) -> Result[Reply?, ProtocolError] {
  if self.failure is Some(error) {
    return Err(error)
  }
  if self.pending is Some(header) {
    let length = match header {
      Reserved(_, length) | Found(_, length) | Ok(length) => length
    }
    let available = self.buffered_bytes()
    if available <= length {
      return Ok(None)
    }
    let end = self.start + length
    if self.data[end] != b'\r' {
      return self.fail(InvalidCrlf)
    }
    if available - length < 2 {
      return Ok(None)
    }
    if self.data[end + 1] != b'\n' {
      return self.fail(InvalidCrlf)
    }
    let body = Bytes::from_array(self.data[self.start:end])
    let reply = match header {
      Reserved(id, _) => Reply::Reserved(id, body)
      Found(id, _) => Reply::Found(id, body)
      Ok(_) => Reply::Ok(body)
    }
    self.start = end + 2
    self.scan = self.start
    self.pending = None
    return Ok(Some(reply))
  }
  while self.scan < self.data.length() {
    let byte = self.data[self.scan]
    if byte == b'\r' {
      if self.scan - self.start > self.max_header {
        return self.fail(HeaderTooLong(self.max_header))
      }
      if self.scan + 1 == self.data.length() {
        return Ok(None)
      }
      if self.data[self.scan + 1] != b'\n' {
        return self.fail(InvalidCrlf)
      }
      let bytes = Bytes::from_array(self.data[self.start:self.scan])
      let line = @utf8.decode_lossy(bytes)
      self.start = self.scan + 2
      self.scan = self.start
      match parse_header(line, self.max_body) {
        Err(error) => return self.fail(error)
        Ok(Complete(reply)) => return Ok(Some(reply))
        Ok(Body(header)) => {
          self.pending = Some(header)
          return self.take()
        }
      }
    }
    if byte == b'\n' {
      return self.fail(InvalidCrlf)
    }
    if byte < b' ' || byte > b'~' {
      return self.fail(MalformedHeader("non-ASCII header"))
    }
    self.scan += 1
    if self.scan - self.start > self.max_header {
      return self.fail(HeaderTooLong(self.max_header))
    }
  }
  Ok(None)
}

///|
/// Signal transport EOF after draining complete replies with take. A partial
/// header, body, or final CRLF poisons the decoder with Truncated.
pub fn Decoder::finish(self : Decoder) -> Result[Unit, ProtocolError] {
  if self.failure is Some(error) {
    return Err(error)
  }
  if self.buffered_bytes() != 0 || self.pending is Some(_) {
    self.failure = Some(Truncated)
    return Err(Truncated)
  }
  Ok(())
}
