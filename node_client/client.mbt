///|
/// A session validation or framing error. Transport errors stay TransportError.
pub suberror RequestError {
  SessionFailure(@client.ClientError)
  InvalidArgument(String)
} derive(@debug.Debug)

///|
pub extend RequestError with @debug.Debug::{to_repr}

///|
/// A Beanstalkd client. No connection pooling, implicit reconnect, or replay.
pub struct Client {
  priv connection : @node_tcp.Connection
  priv session : @client.Session
}

///|
pub async fn connect(
  host : String,
  port : Int32,
  timeout_ms~ : Int32 = 5000,
  max_body~ : Int32 = 1048576,
) -> Client {
  if max_body <= 0 || max_body > 2147482621 {
    raise SessionFailure(Protocol(InvalidLimits))
  }
  let connection = @node_tcp.connect(host, port, timeout_ms~)
  {
    connection,
    session: @client.Session::new(max_body~, max_buffer=max_body + 1026),
  }
}

///|
/// Send one command and receive its complete typed reply. Server statuses are
/// returned as replies; a server TIMED_OUT is distinct from transport TIMEOUT.
/// The timeout covers the entire write/read exchange, not each individual read.
pub async fn Client::execute(
  self : Client,
  command : @protocol.Command,
  timeout_ms~ : Int32 = 5000,
) -> @protocol.Reply {
  if timeout_ms <= 0 {
    raise InvalidArgument("timeout_ms must be positive")
  }
  let encoded = match self.session.begin(command) {
    Ok(bytes) => bytes
    Err(error) => raise SessionFailure(error)
  }
  errdefer self.session.invalidate()
  errdefer self.connection.invalidate()
  let request = self.connection.begin_request(timeout_ms~)
  self.connection.write(request, encoded)
  for chunk = self.connection.read(request) {
    match self.session.feed(chunk) {
      Err(error) => raise SessionFailure(error)
      Ok(None) => continue self.connection.read(request)
      Ok(Some(reply)) => {
        self.connection.finish_request(request)
        break reply
      }
    }
  }
}

///|
pub fn Client::is_open(self : Client) -> Bool {
  self.connection.is_open() && self.session.is_usable()
}

///|
pub fn Client::used_tube(self : Client) -> String {
  self.session.used_tube()
}

///|
/// Close is idempotent and also cancels a pending request.
pub fn Client::close(self : Client) -> Unit {
  self.session.invalidate()
  self.connection.close()
}
