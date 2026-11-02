///|
/// A TCP transport failure. Codes are INVALID_ARGUMENT, CLOSED, BUSY,
/// TIMEOUT, CANCELLED, EOF, or IO. An uncertain operation closes the connection.
pub suberror TransportError {
  TransportError(String, String)
} derive(Debug)

///|
pub extend TransportError with Debug::{to_repr}

///|
/// A Node.js TCP connection. Use exactly one request token at a time.
#external
pub type Connection

///|
/// An owner-bound request token with one absolute monotonic deadline.
#external
pub type Request

///|
#external
priv type Outcome

///|
extern "js" fn Outcome::code(self : Outcome) -> String =
  #| (value) => value.code

///|
extern "js" fn Outcome::message(self : Outcome) -> String =
  #| (value) => value.message

///|
extern "js" fn Outcome::connection(self : Outcome) -> Connection =
  #| (value) => value.connection

///|
extern "js" fn Outcome::bytes(self : Outcome) -> Bytes =
  #| (value) => value.bytes

///|
fn Outcome::check(self : Outcome) -> Unit raise TransportError {
  if self.code() != "" {
    raise TransportError(self.code(), self.message())
  }
}

///|
/// Open a TCP connection. The deadline includes module loading, DNS and TCP.
pub async fn connect(
  host : String,
  port : Int32,
  timeout_ms~ : Int32 = 5000,
) -> Connection {
  let outcome = @js_async.run_promise(signal => {
    raw_connect(host, port, timeout_ms, signal)
  })
  outcome.check()
  outcome.connection()
}

///|
extern "js" fn raw_begin(
  connection : Connection,
  timeout_ms : Int32,
) -> Outcome =
  #| (connection, timeoutMs) => connection.begin(timeoutMs)

///|
extern "js" fn Outcome::request(self : Outcome) -> Request =
  #| (value) => value.request

///|
/// Start an ordered request. Its deadline covers every write and read until finish.
pub fn Connection::begin_request(
  self : Connection,
  timeout_ms~ : Int32 = 5000,
) -> Request raise TransportError {
  let outcome = raw_begin(self, timeout_ms)
  outcome.check()
  outcome.request()
}

///|
extern "js" fn raw_write(
  connection : Connection,
  request : Request,
  bytes : Bytes,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Outcome] =
  #| (connection, request, bytes, signal) => connection.write(request, bytes, signal)

///|
/// Write all bytes and wait for socket flush and backpressure drainage.
/// Cancellation or failure invalidates the connection; never replay an uncertain put.
pub async fn Connection::write(
  self : Connection,
  request : Request,
  bytes : Bytes,
) -> Unit {
  errdefer self.invalidate()
  let outcome = @js_async.run_promise(signal => {
    raw_write(self, request, bytes, signal)
  })
  outcome.check()
}

///|
extern "js" fn raw_read(
  connection : Connection,
  request : Request,
  signal : @js_async.AbortSignal,
) -> @js_async.Promise[Outcome] =
  #| (connection, request, signal) => connection.read(request, signal)

///|
/// Read one nonempty raw chunk (at most 64 KiB). Feed it to a bounded decoder.
/// EOF, cancellation, and timeout invalidate the connection.
pub async fn Connection::read(self : Connection, request : Request) -> Bytes {
  errdefer self.invalidate()
  let outcome = @js_async.run_promise(signal => raw_read(self, request, signal))
  outcome.check()
  outcome.bytes()
}

///|
extern "js" fn raw_finish(
  connection : Connection,
  request : Request,
) -> Outcome =
  #| (connection, request) => connection.finish(request)

///|
/// Release the request only after a complete, validated response has been decoded.
pub fn Connection::finish_request(
  self : Connection,
  request : Request,
) -> Unit raise TransportError {
  raw_finish(self, request).check()
}

///|
/// Permanently close a connection after uncertain framing or protocol failure.
pub extern "js" fn Connection::invalidate(self : Connection) -> Unit =
  #| (connection) => { connection.invalidate("CLOSED", "connection invalidated"); }

///|
/// Close the socket and settle any pending operation. Safe to call repeatedly.
pub extern "js" fn Connection::close(self : Connection) -> Unit =
  #| (connection) => { connection.invalidate("CLOSED", "connection closed"); }

///|
/// True while the socket has not been closed or invalidated.
pub extern "js" fn Connection::is_open(self : Connection) -> Bool =
  #| (connection) => !connection.closed
