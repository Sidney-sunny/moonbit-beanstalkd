///|
async test "tube helpers validate names before sending and preserve acknowledged state" {
  let script = start_script(
    [
      b"use a;b\r\n", b"watch a;b\r\n", b"ignore default\r\n", b"ignore a;b\r\n",
      b"list-tube-used\r\n",
    ],
    [
      b"USING a;b\r\n", b"WATCHING 2\r\n", b"WATCHING 1\r\n", b"NOT_IGNORED\r\n",
      b"USING a;b\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let mut invalid = false
  try {
    let _ = client.use_tube("invalid\r\nwatch other")
  } catch {
    @node_client.SessionFailure(@client.Protocol(@protocol.InvalidTube(_))) =>
      invalid = true
    error => raise error
  }
  assert_true(invalid)
  assert_eq(client.used_tube(), "default")
  assert_true(client.is_open())
  assert_eq(client.use_tube("a;b"), "a;b")
  assert_eq(client.used_tube(), "a;b")
  assert_eq(client.watch("a;b"), 2UL)
  assert_eq(client.watching_count(), 2UL)
  assert_eq(
    client.ignore_tube("default"),
    @node_client.IgnoreOutcome::Watching(1UL),
  )
  assert_eq(client.ignore_tube("a;b"), @node_client.IgnoreOutcome::NotIgnored)
  assert_eq(client.watching_count(), 1UL)
  assert_eq(client.list_tube_used(), "a;b")
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "tube list helpers decode plain and quoted server tube names" {
  let script = start_script([b"list-tubes\r\n", b"list-tubes-watched\r\n"], [
    b"OK 22\r\n---\n- default\n- \"a;b\"\n\r\n", b"OK 12\r\n---\n- \"a;b\"\n\r\n",
  ]).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  assert_eq(client.list_tubes(), ["default", "a;b"])
  assert_eq(client.list_tubes_watched(), ["a;b"])
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "unsupported list YAML raises a document error while complete framing stays reusable" {
  let script = start_script([b"list-tubes\r\n", b"list-tube-used\r\n"], [
    b"OK 11\r\n---\n- &a x\n\r\n", b"USING default\r\n",
  ]).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let mut invalid = false
  try {
    let _ = client.list_tubes()
  } catch {
    @node_client.InvalidDocument(@protocol.InvalidYaml(_)) => invalid = true
    error => raise error
  }
  assert_true(invalid)
  assert_true(client.is_open())
  assert_eq(client.list_tube_used(), "default")
  assert_eq(script.failure(), "")
}
