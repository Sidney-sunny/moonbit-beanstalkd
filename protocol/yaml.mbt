///|
fn yaml_lines(body : Bytes) -> Result[Array[String], ProtocolError] {
  // The server emits LF-separated ASCII scalars. Reject unsupported YAML
  // features instead of presenting this deliberately small parser as YAML.
  for byte in body {
    if byte != b'\n' && (byte < b' ' || byte > b'~') {
      return Err(InvalidYaml("expected LF-separated printable ASCII"))
    }
  }
  if !body.has_prefix(b"---\n") || !body.has_suffix(b"\n") {
    return Err(InvalidYaml("expected document marker and final LF"))
  }
  let text = @utf8.decode_lossy(body)
  let lines = text.split("\n").map(fn(line) { line.to_owned() }).collect()
  Ok(lines[1:lines.length() - 1].to_owned())
}

///|
fn yaml_scalar(value : String) -> Result[String, ProtocolError] {
  let bytes = @utf8.encode(value)
  if bytes.is_empty() {
    return Err(InvalidYaml("empty scalar"))
  }
  if bytes[0] == b'"' {
    if bytes.length() < 2 || bytes[bytes.length() - 1] != b'"' {
      return Err(InvalidYaml("unclosed quoted scalar"))
    }
    let inner = bytes[1:bytes.length() - 1]
    for byte in inner {
      if byte == b'"' || byte == b'\\' {
        return Err(InvalidYaml("escaped or embedded quotes are unsupported"))
      }
    }
    return Ok(@utf8.decode_lossy(inner))
  }
  for byte in bytes {
    if !(byte >= b'a' && byte <= b'z') &&
      !(byte >= b'A' && byte <= b'Z') &&
      !(byte >= b'0' && byte <= b'9') &&
      !(byte == b'-' ||
      byte == b'_' ||
      byte == b'.' ||
      byte == b'/' ||
      byte == b'+' ||
      byte == b';' ||
      byte == b'$' ||
      byte == b'(' ||
      byte == b')') {
      return Err(InvalidYaml("unsupported plain scalar"))
    }
  }
  Ok(value)
}

///|
/// Parse only Beanstalkd's flat ASCII scalar-map YAML subset. Values stay
/// strings, preserving 64-bit integers, decimals, and booleans without loss.
/// Nested objects, aliases, tags, escapes, and duplicate keys are rejected.
pub fn parse_stats(body : Bytes) -> Result[Map[String, String], ProtocolError] {
  let lines = match yaml_lines(body) {
    Ok(lines) => lines
    Err(error) => return Err(error)
  }
  let result : Map[String, String] = Map([])
  for line in lines {
    let (key, value) = match line.split_once(": ") {
      Some((key, value)) => (key.to_owned(), value.to_owned())
      None => return Err(InvalidYaml("expected key: value"))
    }
    if key.is_empty() || result.contains(key) {
      return Err(InvalidYaml("empty or duplicate key"))
    }
    for byte in @utf8.encode(key) {
      if !(byte >= b'a' && byte <= b'z') &&
        !(byte >= b'0' && byte <= b'9') &&
        byte != b'-' {
        return Err(InvalidYaml("unsupported map key"))
      }
    }
    match yaml_scalar(value) {
      Ok(value) => result[key] = value
      Err(error) => return Err(error)
    }
  }
  Ok(result)
}

///|
/// Parse only the flat tube-name list emitted by list-tubes and
/// list-tubes-watched. The tube grammar is the same as command tube names.
pub fn parse_tubes(body : Bytes) -> Result[Array[String], ProtocolError] {
  let lines = match yaml_lines(body) {
    Ok(lines) => lines
    Err(error) => return Err(error)
  }
  let result : Array[String] = []
  for line in lines {
    let scalar = match line.strip_prefix("- ") {
      Some(scalar) => scalar.to_owned()
      None => return Err(InvalidYaml("expected - tube"))
    }
    let tube = match yaml_scalar(scalar) {
      Ok(tube) => tube
      Err(error) => return Err(error)
    }
    if !valid_tube(tube) {
      return Err(InvalidYaml("invalid tube name"))
    }
    result.push(tube)
  }
  Ok(result)
}
