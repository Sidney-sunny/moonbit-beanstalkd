///|
fn valid_tube(tube : String) -> Bool {
  let bytes = @utf8.encode(tube)
  if bytes.length() == 0 || bytes.length() > 200 || bytes[0] == b'-' {
    return false
  }
  for byte in bytes {
    let n = byte.to_int()
    if !(n >= 65 && n <= 90) &&
      !(n >= 97 && n <= 122) &&
      !(n >= 48 && n <= 57) &&
      !(byte == b'-' ||
      byte == b'+' ||
      byte == b'/' ||
      byte == b';' ||
      byte == b'.' ||
      byte == b'$' ||
      byte == b'_' ||
      byte == b'(' ||
      byte == b')') {
      return false
    }
  }
  true
}

///|
/// Encode one command, including the binary body and its CRLF where required.
/// UInt fields accept the complete unsigned 32-bit range; TTR zero is left for
/// the server to normalize to one, as specified by the protocol.
pub fn encode(command : Command) -> Result[Bytes, ProtocolError] {
  let line = match command {
    Use(tube) | Watch(tube) | Ignore(tube) | StatsTube(tube) => {
      if !valid_tube(tube) {
        return Err(InvalidTube(tube))
      }
      let verb = match command {
        Use(_) => "use"
        Watch(_) => "watch"
        Ignore(_) => "ignore"
        _ => "stats-tube"
      }
      "\{verb} \{tube}\r\n"
    }
    Put(priority, delay, ttr, body) => {
      let buffer = @buffer.Buffer()
      buffer.write_string_utf8(
        "put \{priority} \{delay} \{ttr} \{body.length()}\r\n",
      )
      buffer.write_bytes(body)
      buffer.write_bytes(b"\r\n")
      return Ok(buffer.to_bytes())
    }
    ReserveWithTimeout(seconds) => "reserve-with-timeout \{seconds}\r\n"
    Delete(id) => "delete \{id}\r\n"
    Release(id, priority, delay) => "release \{id} \{priority} \{delay}\r\n"
    Bury(id, priority) => "bury \{id} \{priority}\r\n"
    Kick(bound) => "kick \{bound}\r\n"
    KickJob(id) => "kick-job \{id}\r\n"
    Touch(id) => "touch \{id}\r\n"
    Peek(id) => "peek \{id}\r\n"
    PeekReady => "peek-ready\r\n"
    PeekDelayed => "peek-delayed\r\n"
    PeekBuried => "peek-buried\r\n"
    Stats => "stats\r\n"
    StatsJob(id) => "stats-job \{id}\r\n"
    ListTubes => "list-tubes\r\n"
    ListTubeUsed => "list-tube-used\r\n"
    ListTubesWatched => "list-tubes-watched\r\n"
  }
  Ok(@utf8.encode(line))
}
