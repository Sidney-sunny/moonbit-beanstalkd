///|
/// Ignoring the last watched tube is a normal server refusal.
pub(all) enum IgnoreOutcome {
  Watching(UInt64)
  NotIgnored
} derive(Eq, @debug.Debug)

///|
pub extend IgnoreOutcome with Eq::{equal, not_equal}

///|
pub extend IgnoreOutcome with @debug.Debug::{to_repr}

///|
pub async fn Client::use_tube(
  self : Client,
  tube : String,
  timeout_ms~ : Int32 = 5000,
) -> String {
  match self.execute(@protocol.Use(tube), timeout_ms~) {
    Using(actual) => actual
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::watch(
  self : Client,
  tube : String,
  timeout_ms~ : Int32 = 5000,
) -> UInt64 {
  match self.execute(@protocol.Watch(tube), timeout_ms~) {
    Watching(count) => count
    reply => reject_operation(reply)
  }
}

///|
pub async fn Client::ignore_tube(
  self : Client,
  tube : String,
  timeout_ms~ : Int32 = 5000,
) -> IgnoreOutcome {
  match self.execute(@protocol.Ignore(tube), timeout_ms~) {
    Watching(count) => IgnoreOutcome::Watching(count)
    Status(NotIgnored) => IgnoreOutcome::NotIgnored
    reply => reject_operation(reply)
  }
}

///|
/// Last acknowledged watch count; NOT_IGNORED leaves it unchanged.
pub fn Client::watching_count(self : Client) -> UInt64 {
  self.session.watching_count()
}

///|
pub async fn Client::list_tube_used(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> String {
  match self.execute(@protocol.ListTubeUsed, timeout_ms~) {
    Using(tube) => tube
    reply => reject_operation(reply)
  }
}

///|
fn tube_document(reply : @protocol.Reply) -> Array[String] raise OperationError {
  match reply {
    Ok(body) =>
      match @protocol.parse_tubes(body) {
        Ok(tubes) => tubes
        Err(error) => raise InvalidDocument(error)
      }
    reply => reject_operation(reply)
  }
}

///|
/// Decode only Beanstalkd's documented flat tube-name list YAML subset.
pub async fn Client::list_tubes(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Array[String] {
  tube_document(self.execute(@protocol.ListTubes, timeout_ms~))
}

///|
pub async fn Client::list_tubes_watched(
  self : Client,
  timeout_ms~ : Int32 = 5000,
) -> Array[String] {
  tube_document(self.execute(@protocol.ListTubesWatched, timeout_ms~))
}
