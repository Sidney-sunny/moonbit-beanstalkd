///|
#external
priv type Fixture

///|
extern "js" fn start_fixture(mode : String) -> @js_async.Promise[Fixture] =
  #| async (mode) => {
  #|   const net = await import("node:net");
  #|   const sockets = new Set();
  #|   const fixture = { sockets, requests: [], connections: 0 };
  #|   const server = net.createServer(socket => {
  #|     fixture.connections++;
  #|     sockets.add(socket);
  #|     socket.on("error", () => {});
  #|     socket.once("close", () => sockets.delete(socket));
  #|     let input = Buffer.alloc(0);
  #|     socket.on("data", data => {
  #|       input = Buffer.concat([input, data]);
  #|       let end;
  #|       while ((end = input.indexOf("\r\n")) >= 0) {
  #|         const command = input.subarray(0, end).toString("ascii");
  #|         input = input.subarray(end + 2);
  #|         fixture.requests.push(command);
  #|         if (mode === "silent") continue;
  #|         if (mode === "status") {
  #|           socket.write(command.startsWith("reserve-with-timeout ") ? "TIMED_OUT\r\n" : "WATCHING 2\r\n");
  #|         } else if (mode === "fragment") {
  #|           const fragments = [Buffer.from("RESER"), Buffer.from("VED 18446744073709551615 6\r\n"), Buffer.from([0, 13]), Buffer.from([10, 255, 128, 65, 13]), Buffer.from([10])];
  #|           const send = index => {
  #|             if (socket.destroyed || index === fragments.length) return;
  #|             socket.write(fragments[index]);
  #|             setTimeout(() => send(index + 1), 8);
  #|           };
  #|           send(0);
  #|         } else if (mode === "mismatch") {
  #|           socket.write("INSERTED 7\r\n");
  #|         } else if (mode === "delayed") {
  #|           setTimeout(() => { if (!socket.destroyed) socket.write("DELETED\r\n"); }, 75);
  #|         } else if (mode === "trailing") {
  #|           socket.write("DELETED\r\nDELETED\r\n");
  #|         }
  #|       }
  #|     });
  #|   });
  #|   await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  #|   fixture.server = server;
  #|   fixture.port = server.address().port;
  #|   return fixture;
  #| }

///|
extern "js" fn Fixture::port(self : Fixture) -> Int32 =
  #| (fixture) => fixture.port

///|
extern "js" fn Fixture::request_count(self : Fixture) -> Int32 =
  #| (fixture) => fixture.requests.length

///|
extern "js" fn Fixture::connection_count(self : Fixture) -> Int32 =
  #| (fixture) => fixture.connections

///|
extern "js" fn Fixture::close(self : Fixture) -> Unit =
  #| (fixture) => {
  #|   for (const socket of fixture.sockets) socket.destroy();
  #|   fixture.server.close();
  #| }

///|
async fn assert_closed(client : @node_client.Client) -> Unit {
  assert_false(client.is_open())
  let mut rejected = false
  try {
    let _ = client.execute(@protocol.Delete(7UL))
  } catch {
    @node_client.SessionFailure(@client.Closed) => rejected = true
    error => raise error
  }
  assert_true(rejected)
}

///|
async test "coroutine cancellation closes client and rejects subsequent execution" {
  let fixture = start_fixture("silent").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  let result = @async.with_timeout_opt(35, () => {
    client.execute(@protocol.ReserveWithTimeout(30U), timeout_ms=1000)
  })
  assert_true(result is None)
  assert_eq(fixture.request_count(), 1)
  assert_closed(client)
  assert_eq(fixture.request_count(), 1)
}

///|
async test "transport deadline is TIMEOUT and invalidates client" {
  let fixture = start_fixture("silent").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  let mut timed_out = false
  try {
    let _ = client.execute(@protocol.ReserveWithTimeout(30U), timeout_ms=35)
  } catch {
    @node_tcp.TransportError("TIMEOUT", _) => timed_out = true
    error => raise error
  }
  assert_true(timed_out)
  assert_closed(client)
  assert_eq(fixture.request_count(), 1)
}

///|
async test "server TIMED_OUT is a typed reply and permits another command" {
  let fixture = start_fixture("status").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  assert_true(client.is_open())
  assert_eq(client.execute(@protocol.Watch("binary")), @protocol.Watching(2UL))
  assert_true(client.is_open())
  assert_eq(fixture.request_count(), 2)
}

///|
async test "fragmented TCP reply preserves binary payload and full UInt64 job ID" {
  let fixture = start_fixture("fragment").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Reserved(18446744073709551615UL, b"\x00\r\n\xff\x80A"),
  )
  assert_true(client.is_open())
  assert_eq(fixture.request_count(), 1)
}

///|
async test "reply mismatching command invalidates client without replay" {
  let fixture = start_fixture("mismatch").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  let mut rejected = false
  try {
    let _ = client.execute(@protocol.Delete(7UL))
  } catch {
    @node_client.SessionFailure(@client.UnexpectedReply) => rejected = true
    error => raise error
  }
  assert_true(rejected)
  assert_closed(client)
  assert_eq(fixture.request_count(), 1)
}

///|
async test "concurrent execution reports BUSY without cancelling first request" {
  let fixture = start_fixture("delayed").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  @async.with_task_group(group => {
    let first = group.spawn(() => client.execute(@protocol.Delete(7UL)))
    @async.with_timeout(1000, () => {
      while fixture.request_count() == 0 {
        @async.sleep(1)
      }
    })
    let mut busy = false
    try {
      let _ = client.execute(@protocol.Delete(8UL))
    } catch {
      @node_client.SessionFailure(@client.Busy) => busy = true
      error => raise error
    }
    assert_true(busy)
    assert_true(client.is_open())
    assert_eq(first.wait(), @protocol.Status(Deleted))
    assert_true(client.is_open())
  })
  assert_eq(fixture.request_count(), 1)
}

///|
async test "trailing reply bytes cannot become a subsequent command response" {
  let fixture = start_fixture("trailing").wait()
  defer fixture.close()
  let client = @node_client.connect("127.0.0.1", fixture.port())
  defer client.close()
  let mut rejected = false
  try {
    let _ = client.execute(@protocol.Delete(7UL))
  } catch {
    @node_client.SessionFailure(@client.UnsolicitedData) => rejected = true
    error => raise error
  }
  assert_true(rejected)
  assert_closed(client)
  assert_eq(fixture.request_count(), 1)
}

///|
async test "invalid constructor limits reject before opening a TCP connection" {
  let fixture = start_fixture("silent").wait()
  defer fixture.close()
  for max_body in [0, -1, 2147482622] {
    let mut rejected = false
    try {
      let client = @node_client.connect("127.0.0.1", fixture.port(), max_body~)
      client.close()
    } catch {
      @node_client.SessionFailure(@client.Protocol(InvalidLimits)) =>
        rejected = true
      error => raise error
    }
    assert_true(rejected)
  }
  @async.sleep(20)
  assert_eq(fixture.connection_count(), 0)
}
