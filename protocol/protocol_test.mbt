///|
fn drain(decoder : @protocol.Decoder) -> Array[@protocol.Reply] raise {
  let replies = []
  while true {
    match decoder.take() {
      Ok(Some(reply)) => replies.push(reply)
      Ok(None) => break
      Err(error) => fail(@debug.to_string(error))
    }
  }
  replies
}

// Independent literal wire transcripts follow the Beanstalkd v1.13 protocol,
// https://github.com/beanstalkd/beanstalkd/blob/v1.13/doc/protocol.txt.
// These are authored protocol examples, not encoder-generated round trips.

///|
test "encode all supported commands against literal wire transcripts" {
  let cases : Array[(@protocol.Command, Bytes)] = [
    (@protocol.Use("work"), b"use work\r\n"),
    (@protocol.Watch("work"), b"watch work\r\n"),
    (@protocol.Ignore("default"), b"ignore default\r\n"),
    (
      @protocol.Put(4294967295U, 4294967295U, 4294967295U, b"a\x00\r\nb"),
      b"put 4294967295 4294967295 4294967295 5\r\na\x00\r\nb\r\n",
    ),
    (@protocol.ReserveWithTimeout(0U), b"reserve-with-timeout 0\r\n"),
    (
      @protocol.Delete(18446744073709551615UL),
      b"delete 18446744073709551615\r\n",
    ),
    (@protocol.Release(42UL, 10U, 3U), b"release 42 10 3\r\n"),
    (@protocol.Bury(42UL, 10U), b"bury 42 10\r\n"),
    (@protocol.Kick(12U), b"kick 12\r\n"),
    (@protocol.KickJob(42UL), b"kick-job 42\r\n"),
    (@protocol.Touch(42UL), b"touch 42\r\n"),
    (@protocol.Peek(42UL), b"peek 42\r\n"),
    (@protocol.PeekReady, b"peek-ready\r\n"),
    (@protocol.PeekDelayed, b"peek-delayed\r\n"),
    (@protocol.PeekBuried, b"peek-buried\r\n"),
    (@protocol.Stats, b"stats\r\n"),
    (@protocol.StatsJob(42UL), b"stats-job 42\r\n"),
    (@protocol.StatsTube("work"), b"stats-tube work\r\n"),
    (@protocol.ListTubes, b"list-tubes\r\n"),
    (@protocol.ListTubeUsed, b"list-tube-used\r\n"),
    (@protocol.ListTubesWatched, b"list-tubes-watched\r\n"),
  ]
  for (command, wire) in cases {
    @debug.assert_eq(@protocol.encode(command), Ok(wire))
  }
}

///|
test "tube validation prevents command injection and permits protocol alphabet" {
  for
    tube in [
      "",
      "-start",
      "a b",
      "a\r\nput 0 0 1 1",
      "a\u0000b",
      "中文",
      String::make(201, 'x'),
    ] {
    @debug.assert_eq(
      @protocol.encode(@protocol.Use(tube)),
      Err(@protocol.InvalidTube(tube)),
    )
  }
  let tube = "AZaz09-+/;.$_()"
  @debug.assert_eq(
    @protocol.encode(@protocol.Use(tube)),
    Ok(b"use AZaz09-+/;.$_()\r\n"),
  )
  let boundary = String::make(200, 'x')
  assert_true(@protocol.encode(@protocol.Watch(boundary)) is Ok(_))
}

///|
test "incremental replies survive every split and individual byte chunks" {
  let cases : Array[(Bytes, @protocol.Reply)] = [
    (
      b"INSERTED 18446744073709551615\r\n",
      @protocol.Inserted(18446744073709551615UL),
    ),
    (b"BURIED 42\r\n", @protocol.Reply::Buried(42UL)),
    (b"USING jobs_1\r\n", @protocol.Using("jobs_1")),
    (b"WATCHING 2\r\n", @protocol.Watching(2UL)),
    (b"KICKED 4\r\n", @protocol.Reply::Kicked(4UL)),
    (
      b"RESERVED 18446744073709551615 5\r\na\x00\r\nb\r\n",
      @protocol.Reserved(18446744073709551615UL, b"a\x00\r\nb"),
    ),
    (b"FOUND 42 0\r\n\r\n", @protocol.Found(42UL, b"")),
    (
      b"OK 16\r\n---\n- jobs\n- q\n\n\r\n",
      @protocol.Reply::Ok(b"---\n- jobs\n- q\n\n"),
    ),
    (b"TIMED_OUT\r\n", @protocol.Status(@protocol.TimedOut)),
  ]
  for (wire, expected) in cases {
    for split in 0..<=wire.length() {
      let decoder = @protocol.Decoder::new()
      @debug.assert_eq(decoder.feed(wire[:split].to_owned()), Ok(()))
      let replies = drain(decoder)
      @debug.assert_eq(decoder.feed(wire[split:].to_owned()), Ok(()))
      replies.push_iter(drain(decoder).iter())
      @debug.assert_eq(replies, [expected])
      @debug.assert_eq(decoder.finish(), Ok(()))
    }
    let decoder = @protocol.Decoder::new()
    let replies = []
    for byte in wire {
      @debug.assert_eq(decoder.feed(Bytes::make(1, byte)), Ok(()))
      replies.push_iter(drain(decoder).iter())
    }
    @debug.assert_eq(replies, [expected])
    @debug.assert_eq(decoder.finish(), Ok(()))
  }
}

///|
test "coalesced replies retain exact framing between messages" {
  let decoder = @protocol.Decoder::new()
  @debug.assert_eq(
    decoder.feed(b"FOUND 1 2\r\n\x00\xff\r\nDELETED\r\nINSERTED 2\r\n"),
    Ok(()),
  )
  @debug.assert_eq(drain(decoder), [
    @protocol.Found(1UL, b"\x00\xff"),
    @protocol.Status(@protocol.Deleted),
    @protocol.Inserted(2UL),
  ])
  @debug.assert_eq(decoder.buffered_bytes(), 0)
  @debug.assert_eq(decoder.finish(), Ok(()))
}

///|
test "all documented bare statuses are distinct from local framing errors" {
  let cases : Array[(Bytes, @protocol.ServerStatus)] = [
    (b"DELETED\r\n", @protocol.Deleted),
    (b"RELEASED\r\n", @protocol.Released),
    (b"BURIED\r\n", @protocol.ServerStatus::Buried),
    (b"KICKED\r\n", @protocol.ServerStatus::Kicked),
    (b"TOUCHED\r\n", @protocol.Touched),
    (b"TIMED_OUT\r\n", @protocol.TimedOut),
    (b"DEADLINE_SOON\r\n", @protocol.DeadlineSoon),
    (b"NOT_FOUND\r\n", @protocol.NotFound),
    (b"NOT_IGNORED\r\n", @protocol.NotIgnored),
    (b"JOB_TOO_BIG\r\n", @protocol.JobTooBig),
    (b"DRAINING\r\n", @protocol.Draining),
    (b"EXPECTED_CRLF\r\n", @protocol.ExpectedCrlf),
    (b"OUT_OF_MEMORY\r\n", @protocol.OutOfMemory),
    (b"INTERNAL_ERROR\r\n", @protocol.InternalError),
    (b"BAD_FORMAT\r\n", @protocol.BadFormat),
    (b"UNKNOWN_COMMAND\r\n", @protocol.UnknownCommand),
  ]
  for (wire, status) in cases {
    let decoder = @protocol.Decoder::new()
    @debug.assert_eq(decoder.feed(wire), Ok(()))
    @debug.assert_eq(decoder.take(), Ok(Some(@protocol.Status(status))))
  }
}

///|
test "malformed replies poison the decoder without resynchronization" {
  let cases : Array[(Bytes, @protocol.ProtocolError)] = [
    (b"DELETED\n", @protocol.InvalidCrlf),
    (b"DELETED\rX", @protocol.InvalidCrlf),
    (b"FOUND 1 1\r\nx\n\n", @protocol.InvalidCrlf),
    (b"INSERTED -1\r\n", @protocol.MalformedHeader("-1")),
    (b"INSERTED +1\r\n", @protocol.MalformedHeader("+1")),
    (
      b"INSERTED 18446744073709551616\r\n",
      @protocol.IntegerOverflow("18446744073709551616"),
    ),
    (
      b"FOUND 1 18446744073709551616\r\n",
      @protocol.IntegerOverflow("18446744073709551616"),
    ),
    (b"INSERTED  1\r\n", @protocol.MalformedHeader("INSERTED  1")),
    (b"OK x\r\n", @protocol.MalformedHeader("x")),
    (b"USING -bad\r\n", @protocol.MalformedHeader("USING -bad")),
    (b"DELETED extra\r\n", @protocol.MalformedHeader("DELETED extra")),
    (b"\x00\r\n", @protocol.MalformedHeader("non-ASCII header")),
  ]
  for (wire, error) in cases {
    let decoder = @protocol.Decoder::new()
    @debug.assert_eq(decoder.feed(wire), Ok(()))
    @debug.assert_eq(decoder.take(), Err(error))
    @debug.assert_eq(decoder.feed(b"DELETED\r\n"), Err(error))
    @debug.assert_eq(decoder.take(), Err(error))
    @debug.assert_eq(decoder.finish(), Err(error))
  }
}

///|
test "limits reject oversized headers bodies and buffers before allocation" {
  let decoder = @protocol.Decoder::new(max_header=7)
  @debug.assert_eq(decoder.feed(b"DELETED\r\n"), Ok(()))
  @debug.assert_eq(
    decoder.take(),
    Ok(Some(@protocol.Status(@protocol.Deleted))),
  )
  @debug.assert_eq(decoder.feed(b"DEADLINE"), Ok(()))
  @debug.assert_eq(decoder.take(), Err(@protocol.HeaderTooLong(7)))
  let decoder = @protocol.Decoder::new(max_body=3)
  @debug.assert_eq(decoder.feed(b"FOUND 1 4\r\n"), Ok(()))
  @debug.assert_eq(decoder.take(), Err(@protocol.BodyTooLarge(4UL)))
  let decoder = @protocol.Decoder::new(max_buffer=3)
  @debug.assert_eq(decoder.feed(b"abc"), Ok(()))
  @debug.assert_eq(decoder.feed(b"d"), Err(@protocol.BufferTooLarge(3)))
  let decoder = @protocol.Decoder::new(max_header=0)
  @debug.assert_eq(decoder.feed(b""), Err(@protocol.InvalidLimits))
}

///|
test "EOF identifies every incomplete header body and terminator" {
  for wire in [b"INSERTED 1\r\n", b"RESERVED 1 3\r\na\x00b\r\n"] {
    for end in 1..<wire.length() {
      let decoder = @protocol.Decoder::new()
      @debug.assert_eq(decoder.feed(wire[:end].to_owned()), Ok(()))
      @debug.assert_eq(decoder.take(), Ok(None))
      @debug.assert_eq(decoder.finish(), Err(@protocol.Truncated))
    }
  }
}

///|
test "documented flat YAML preserves exact scalar values and tube names" {
  @debug.assert_eq(
    @protocol.parse_stats(
      b"---\nid: 18446744073709551615\nstate: ready\nversion: \"1.13\"\ndraining: false\nrusage-utime: 0.000001\n",
    ),
    Ok({
      "id": "18446744073709551615",
      "state": "ready",
      "version": "1.13",
      "draining": "false",
      "rusage-utime": "0.000001",
    }),
  )
  @debug.assert_eq(
    @protocol.parse_tubes(b"---\n- default\n- \"jobs_1\"\n"),
    Ok(["default", "jobs_1"]),
  )
  @debug.assert_eq(@protocol.parse_tubes(b"---\n"), Ok([]))
  for
    body in [
      b"id: 1\n", b"---\nid: 1", b"---\nid: 1\nid: 2\n", b"---\na: [1]\n", b"---\na: &ref\n",
      b"---\na: \"broken\n", b"---\na: \"a\\nb\"\n", b"---\na: \xff\n",
    ] {
    assert_true(@protocol.parse_stats(body) is Err(_))
  }
  for body in [b"---\n- -bad\n", b"---\n- a b\n", b"---\na: 1\n"] {
    assert_true(@protocol.parse_tubes(body) is Err(_))
  }
}

///|
test "all byte values remain opaque and invalid body CRLF fails immediately" {
  let payload = Bytes::makei(256, fn(index) { index.to_byte() })
  let decoder = @protocol.Decoder::new(max_body=256)
  @debug.assert_eq(decoder.feed(b"RESERVED 42 256\r\n"), Ok(()))
  @debug.assert_eq(decoder.take(), Ok(None))
  for byte in payload {
    @debug.assert_eq(decoder.feed(Bytes::make(1, byte)), Ok(()))
    @debug.assert_eq(decoder.take(), Ok(None))
  }
  @debug.assert_eq(decoder.feed(b"\r"), Ok(()))
  @debug.assert_eq(decoder.take(), Ok(None))
  @debug.assert_eq(decoder.feed(b"\n"), Ok(()))
  @debug.assert_eq(decoder.take(), Ok(Some(@protocol.Reserved(42UL, payload))))
  let decoder = @protocol.Decoder::new()
  @debug.assert_eq(decoder.feed(b"FOUND 1 0\r\nx"), Ok(()))
  @debug.assert_eq(decoder.take(), Err(@protocol.InvalidCrlf))
}
