///|
#external
priv type Script

///|
/// Literal independent wire transcripts over real TCP, shared by helper tests.
extern "js" fn start_script(
  commands : FixedArray[Bytes],
  replies : FixedArray[Bytes],
) -> @js_async.Promise[Script] =
  #| async (commands, replies) => {
  #|   const net = await import("node:net");
  #|   const script = { sockets: new Set(), index: 0, failure: "" };
  #|   const server = net.createServer(socket => {
  #|     script.sockets.add(socket);
  #|     socket.on("error", () => {});
  #|     socket.once("close", () => script.sockets.delete(socket));
  #|     let input = Buffer.alloc(0);
  #|     socket.on("data", chunk => {
  #|       input = Buffer.concat([input, chunk]);
  #|       if (script.index >= commands.length) {
  #|         script.failure = "unexpected extra command";
  #|         socket.destroy();
  #|         return;
  #|       }
  #|       const expected = Buffer.from(commands[script.index]);
  #|       if (input.length < expected.length) return;
  #|       if (!input.subarray(0, expected.length).equals(expected)) {
  #|         script.failure = `wire command mismatch at step ${script.index}`;
  #|         socket.destroy();
  #|         return;
  #|       }
  #|       input = input.subarray(expected.length);
  #|       if (input.length !== 0) script.failure = "pipelined command before reply";
  #|       const reply = Buffer.from(replies[script.index++]);
  #|       socket.write(reply.subarray(0, 1));
  #|       setTimeout(() => { if (!socket.destroyed) socket.write(reply.subarray(1)); }, 2);
  #|     });
  #|   });
  #|   await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  #|   script.server = server;
  #|   script.port = server.address().port;
  #|   script.expected = commands.length;
  #|   return script;
  #| }

///|
extern "js" fn Script::port(self : Script) -> Int32 =
  #| (script) => script.port

///|
extern "js" fn Script::failure(self : Script) -> String =
  #| (script) => script.failure || (script.index !== script.expected ? "missing expected command" : "")

///|
extern "js" fn Script::close(self : Script) -> Unit =
  #| (script) => {
  #|   for (const socket of script.sockets) socket.destroy();
  #|   script.server.close();
  #| }

///|
async test "job helpers preserve buried acceptance binary bodies and UInt64 IDs" {
  let script = start_script(
    [
      b"put 4294967295 4294967295 4294967295 3\r\n\x00\r\n\r\n", b"reserve-with-timeout 0\r\n",
      b"delete 18446744073709551615\r\n",
    ],
    [
      b"BURIED 18446744073709551615\r\n", b"RESERVED 18446744073709551615 3\r\n\x00\r\n\r\n",
      b"DELETED\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  assert_eq(
    client.put(
      b"\x00\r\n",
      priority=4294967295U,
      delay=4294967295U,
      ttr=4294967295U,
    ),
    @node_client.PutOutcome::Buried(18446744073709551615UL),
  )
  assert_eq(
    client.reserve(),
    @node_client.ReserveOutcome::Reserved({
      id: 18446744073709551615UL,
      body: b"\x00\r\n",
    }),
  )
  assert_true(client.delete(18446744073709551615UL))
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "reserve and release expose expected non-success states without closing" {
  let script = start_script(
    [
      b"reserve-with-timeout 0\r\n", b"reserve-with-timeout 2\r\n", b"release 7 3 4\r\n",
      b"release 7 0 0\r\n", b"release 7 0 0\r\n",
    ],
    [
      b"TIMED_OUT\r\n", b"DEADLINE_SOON\r\n", b"BURIED\r\n", b"NOT_FOUND\r\n", b"RELEASED\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  assert_eq(client.reserve(), @node_client.ReserveOutcome::TimedOut)
  assert_eq(
    client.reserve(timeout_seconds=2U),
    @node_client.ReserveOutcome::DeadlineSoon,
  )
  assert_eq(
    client.release(7UL, priority=3U, delay=4U),
    @node_client.ReleaseOutcome::Buried,
  )
  assert_eq(client.release(7UL), @node_client.ReleaseOutcome::NotFound)
  assert_eq(client.release(7UL), @node_client.ReleaseOutcome::Released)
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "job mutation helpers expose missing jobs and keep the connection usable" {
  let script = start_script(
    [
      b"delete 7\r\n", b"bury 7 2\r\n", b"touch 7\r\n", b"kick-job 7\r\n", b"kick 3\r\n",
      b"touch 8\r\n", b"bury 8 0\r\n", b"kick-job 8\r\n",
    ],
    [
      b"NOT_FOUND\r\n", b"NOT_FOUND\r\n", b"NOT_FOUND\r\n", b"NOT_FOUND\r\n", b"KICKED 2\r\n",
      b"TOUCHED\r\n", b"BURIED\r\n", b"KICKED\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  assert_false(client.delete(7UL))
  assert_false(client.bury(7UL, priority=2U))
  assert_false(client.touch(7UL))
  assert_false(client.kick_job(7UL))
  assert_eq(client.kick(3U), 2UL)
  assert_true(client.touch(8UL))
  assert_true(client.bury(8UL))
  assert_true(client.kick_job(8UL))
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "rejected put raises exact server status without losing synchronization" {
  let script = start_script(
    [b"put 0 0 60 1\r\nx\r\n", b"put 0 0 60 1\r\ny\r\n"],
    [b"DRAINING\r\n", b"INSERTED 9\r\n"],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let mut rejected = false
  try {
    let _ = client.put(b"x")
  } catch {
    @node_client.ServerRejected(@protocol.Draining) => rejected = true
    error => raise error
  }
  assert_true(rejected)
  assert_true(client.is_open())
  assert_eq(client.put(b"y"), @node_client.PutOutcome::Inserted(9UL))
  assert_eq(script.failure(), "")
}
