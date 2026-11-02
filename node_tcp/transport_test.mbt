///|
#external
priv type Fixture

///|
extern "js" fn start_fixture(mode : String) -> @js_async.Promise[Fixture] =
  #| async (mode) => {
  #|   const net = await import("node:net");
  #|   const sockets = new Set();
  #|   const server = net.createServer(socket => {
  #|     sockets.add(socket);
  #|     socket.on("error", () => {});
  #|     socket.once("close", () => sockets.delete(socket));
  #|     if (mode === "silent") return;
  #|     socket.on("data", data => {
  #|       socket.write(data.subarray(0, 1));
  #|       setTimeout(() => { if (!socket.destroyed) socket.write(data.subarray(1)); }, 20);
  #|     });
  #|   });
  #|   await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  #|   return { server, sockets, port: server.address().port };
  #| }

///|
extern "js" fn Fixture::port(self : Fixture) -> Int32 =
  #| (fixture) => fixture.port

///|
extern "js" fn Fixture::close(self : Fixture) -> Unit =
  #| (fixture) => {
  #|   for (const socket of fixture.sockets) socket.destroy();
  #|   fixture.server.close();
  #| }

///|
async test "MoonBit FFI preserves bytes and receives fragmented real TCP" {
  let fixture = start_fixture("echo").wait()
  defer fixture.close()
  let connection = @node_tcp.connect("127.0.0.1", fixture.port())
  defer connection.close()
  let request = connection.begin_request()
  let payload = b"\x00\r\n\xff\x80A"
  connection.write(request, payload)
  let received : Array[Byte] = []
  while received.length() < payload.length() {
    let chunk = connection.read(request)
    for byte in chunk {
      received.push(byte)
    }
  }
  assert_eq(Bytes::from_array(received), payload)
  connection.finish_request(request)
  assert_true(connection.is_open())
}

///|
async test "MoonBit FFI absolute request deadline invalidates connection" {
  let fixture = start_fixture("silent").wait()
  defer fixture.close()
  let connection = @node_tcp.connect("127.0.0.1", fixture.port())
  defer connection.close()
  let request = connection.begin_request(timeout_ms=35)
  let mut timed_out = false
  try {
    let _ = connection.read(request)
  } catch {
    @node_tcp.TransportError("TIMEOUT", _) => timed_out = true
    error => raise error
  }
  assert_true(timed_out)
  assert_false(connection.is_open())
}

///|
async test "MoonBit coroutine cancellation invalidates the TCP connection" {
  let fixture = start_fixture("silent").wait()
  defer fixture.close()
  let connection = @node_tcp.connect("127.0.0.1", fixture.port())
  defer connection.close()
  let request = connection.begin_request(timeout_ms=1000)
  let result = @async.with_timeout_opt(35, () => connection.read(request))
  assert_true(result is None)
  assert_false(connection.is_open())
}
