///|
fn stats_document(
  reply : @protocol.Reply,
) -> Map[String, String] raise OperationError {
  match reply {
    Ok(body) =>
      match @protocol.parse_stats(body) {
        Ok(stats) => stats
        Err(error) => raise InvalidDocument(error)
      }
    reply => reject_operation(reply)
  }
}

///|
/// Parse only the server's flat scalar-map YAML subset. Numeric scalars remain
/// strings, preserving integer precision and server-defined decimal values.
pub async fn Client::stats(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Map[String, String] {
  stats_document(self.execute(@protocol.Stats, timeout_ms~))
}

///|
fn[T] Client::inspection_mismatch(self : Client) -> T raise RequestError {
  self.session.invalidate()
  self.connection.invalidate()
  raise SessionFailure(UnexpectedReply)
}

///|
/// Return None for NOT_FOUND. Require the document's id to identify this job;
/// other scalar fields stay strings and are not interpreted as a full schema.
pub async fn Client::stats_job(
  self : Client,
  id : UInt64,
  timeout_ms~ : Int32 = 5000,
) -> Map[String, String]? {
  let reply = self.execute(@protocol.StatsJob(id), timeout_ms~)
  if reply is Status(NotFound) {
    return None
  }
  let stats = stats_document(reply)
  if stats.get("id") != Some(id.to_string()) {
    return self.inspection_mismatch()
  }
  Some(stats)
}

///|
/// Return None for NOT_FOUND and verify the required name scalar. Missing or
/// mismatched identity invalidates the connection instead of trusting the reply.
pub async fn Client::stats_tube(
  self : Client,
  tube : String,
  timeout_ms~ : Int32 = 5000,
) -> Map[String, String]? {
  let reply = self.execute(@protocol.StatsTube(tube), timeout_ms~)
  if reply is Status(NotFound) {
    return None
  }
  let stats = stats_document(reply)
  if stats.get("name") != Some(tube) {
    return self.inspection_mismatch()
  }
  Some(stats)
}

///|
fn found_job(reply : @protocol.Reply) -> Job? raise OperationError {
  match reply {
    Found(id, body) => Some({ id, body, })
    Status(NotFound) => None
    reply => reject_operation(reply)
  }
}

///|
/// Inspect a job without reserving it. Session matching requires the exact id.
pub async fn Client::peek(
  self : Client,
  id : UInt64,
  timeout_ms~ : Int32 = 5000,
) -> Job? {
  found_job(self.execute(@protocol.Peek(id), timeout_ms~))
}

///|
pub async fn Client::peek_ready(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Job? {
  found_job(self.execute(@protocol.PeekReady, timeout_ms~))
}

///|
pub async fn Client::peek_delayed(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Job? {
  found_job(self.execute(@protocol.PeekDelayed, timeout_ms~))
}

///|
pub async fn Client::peek_buried(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Job? {
  found_job(self.execute(@protocol.PeekBuried, timeout_ms~))
}
