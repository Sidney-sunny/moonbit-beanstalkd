///|
async test "stats helpers preserve scalar precision and expose missing job or tube" {
  let script = start_script(
    [
      b"stats\r\n", b"stats-job 18446744073709551615\r\n", b"stats-tube a;b\r\n",
      b"stats-job 7\r\n", b"stats-tube absent\r\n",
    ],
    [
      b"OK 80\r\n---\ncurrent-jobs-ready: 9007199254740993\nrusage-utime: 0.000001\nversion: \"1.13\"\n\r\n",
      b"OK 45\r\n---\nid: 18446744073709551615\npri: 4294967295\n\r\n", b"OK 53\r\n---\nname: \"a;b\"\ncurrent-jobs-ready: 9007199254740993\n\r\n",
      b"NOT_FOUND\r\n", b"NOT_FOUND\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let stats = client.stats()
  assert_eq(stats.get("current-jobs-ready"), Some("9007199254740993"))
  assert_eq(stats.get("rusage-utime"), Some("0.000001"))
  assert_eq(stats.get("version"), Some("1.13"))
  let job = match client.stats_job(18446744073709551615UL) {
    Some(stats) => stats
    None => fail("expected existing job stats")
  }
  assert_eq(job.get("id"), Some("18446744073709551615"))
  assert_eq(job.get("pri"), Some("4294967295"))
  let tube = match client.stats_tube("a;b") {
    Some(stats) => stats
    None => fail("expected existing tube stats")
  }
  assert_eq(tube.get("name"), Some("a;b"))
  assert_eq(tube.get("current-jobs-ready"), Some("9007199254740993"))
  assert_true(client.stats_job(7UL) is None)
  assert_true(client.stats_tube("absent") is None)
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "peek variants return exact opaque jobs or None without reservation" {
  let script = start_script(
    [
      b"peek 18446744073709551615\r\n", b"peek-ready\r\n", b"peek-delayed\r\n", b"peek-buried\r\n",
      b"peek 7\r\n", b"peek-ready\r\n", b"peek-delayed\r\n", b"peek-buried\r\n",
    ],
    [
      b"FOUND 18446744073709551615 4\r\n\x00\r\n\xff\r\n", b"FOUND 3 1\r\nx\r\n",
      b"NOT_FOUND\r\n", b"FOUND 4 0\r\n\r\n", b"NOT_FOUND\r\n", b"NOT_FOUND\r\n",
      b"FOUND 5 1\r\ny\r\n", b"NOT_FOUND\r\n",
    ],
  ).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  assert_eq(
    client.peek(18446744073709551615UL),
    Some(@node_client.Job::{
      id: 18446744073709551615UL,
      body: b"\x00\r\n\xff",
    }),
  )
  assert_eq(
    client.peek_ready(),
    Some(@node_client.Job::{ id: 3UL, body: b"x", }),
  )
  assert_true(client.peek_delayed() is None)
  assert_eq(
    client.peek_buried(),
    Some(@node_client.Job::{ id: 4UL, body: b"", }),
  )
  assert_true(client.peek(7UL) is None)
  assert_true(client.peek_ready() is None)
  assert_eq(
    client.peek_delayed(),
    Some(@node_client.Job::{ id: 5UL, body: b"y", }),
  )
  assert_true(client.peek_buried() is None)
  assert_true(client.is_open())
  assert_eq(script.failure(), "")
}

///|
async test "stats identity mismatch or missing identity closes the correlated session" {
  let cases = [
    (true, b"stats-job 7\r\n", b"OK 10\r\n---\nid: 8\n\r\n"),
    (false, b"stats-tube a;b\r\n", b"OK 16\r\n---\nname: other\n\r\n"),
    (true, b"stats-job 7\r\n", b"OK 11\r\n---\npri: 0\n\r\n"),
    (false, b"stats-tube a;b\r\n", b"OK 26\r\n---\ncurrent-jobs-ready: 0\n\r\n"),
  ]
  for (is_job, command, reply) in cases {
    let script = start_script([command], [reply]).wait()
    defer script.close()
    let client = @node_client.connect("127.0.0.1", script.port())
    defer client.close()
    let mut mismatch = false
    try {
      let _ = if is_job {
        client.stats_job(7UL)
      } else {
        client.stats_tube("a;b")
      }
    } catch {
      @node_client.SessionFailure(@client.UnexpectedReply) => mismatch = true
      error => raise error
    }
    assert_true(mismatch)
    assert_closed(client)
    assert_eq(script.failure(), "")
  }
}

///|
async test "unsupported stats YAML is a document failure with reusable complete framing" {
  let script = start_script([b"stats-job 7\r\n", b"stats\r\n"], [
    b"OK 18\r\n---\nid: &anchor 7\n\r\n", b"OK 26\r\n---\ncurrent-jobs-ready: 0\n\r\n",
  ]).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let mut invalid = false
  try {
    let _ = client.stats_job(7UL)
  } catch {
    @node_client.InvalidDocument(@protocol.InvalidYaml(_)) => invalid = true
    error => raise error
  }
  assert_true(invalid)
  assert_true(client.is_open())
  assert_eq(client.stats().get("current-jobs-ready"), Some("0"))
  assert_eq(script.failure(), "")
}

///|
async test "peek helper rejects a found job with the wrong requested id" {
  let script = start_script([b"peek 7\r\n"], [b"FOUND 8 1\r\nx\r\n"]).wait()
  defer script.close()
  let client = @node_client.connect("127.0.0.1", script.port())
  defer client.close()
  let mut mismatch = false
  try {
    let _ = client.peek(7UL)
  } catch {
    @node_client.SessionFailure(@client.UnexpectedReply) => mismatch = true
    error => raise error
  }
  assert_true(mismatch)
  assert_closed(client)
  assert_eq(script.failure(), "")
}
