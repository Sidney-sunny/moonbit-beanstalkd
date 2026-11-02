// Adapted from go-beanstalk conn_test.go at
// 52e4a01c453b3de42105389beb2374f256751064.
// Copyright 2012 Keith Rarick. MIT license: see protocol/NOTICE.
// Literal command/reply bytes are preserved as the independent oracle.

///|
test "pinned Go reference transcripts encode and decode at every split" {
  let cases : Array[
    (String, Array[@protocol.Command], Bytes, Bytes, Array[@protocol.Reply]),
  ] = [
    (
      "TestDeleteMissing",
      [@protocol.Delete(1UL)],
      b"delete 1\r\n",
      b"NOT_FOUND\r\n",
      [@protocol.Status(@protocol.NotFound)],
    ),
    (
      "TestUse",
      [@protocol.Use("foo"), @protocol.Put(0U, 0U, 0U, b"hello")],
      b"use foo\r\nput 0 0 0 5\r\nhello\r\n",
      b"USING foo\r\nINSERTED 1\r\n",
      [@protocol.Using("foo"), @protocol.Inserted(1UL)],
    ),
    (
      "TestWatchIgnore",
      [
        @protocol.Watch("foo"),
        @protocol.Ignore("default"),
        @protocol.ReserveWithTimeout(1U),
      ],
      b"watch foo\r\nignore default\r\nreserve-with-timeout 1\r\n",
      b"WATCHING 2\r\nWATCHING 1\r\nRESERVED 1 1\r\nx\r\n",
      [
        @protocol.Watching(2UL),
        @protocol.Watching(1UL),
        @protocol.Reserved(1UL, b"x"),
      ],
    ),
    (
      "TestBury",
      [@protocol.Bury(1UL, 3U)],
      b"bury 1 3\r\n",
      b"BURIED\r\n",
      [@protocol.Status(@protocol.ServerStatus::Buried)],
    ),
    (
      "TestTubeKickJob",
      [@protocol.KickJob(3UL)],
      b"kick-job 3\r\n",
      b"KICKED\r\n",
      [@protocol.Status(@protocol.ServerStatus::Kicked)],
    ),
    (
      "TestDelete",
      [@protocol.Delete(1UL)],
      b"delete 1\r\n",
      b"DELETED\r\n",
      [@protocol.Status(@protocol.Deleted)],
    ),
    (
      "TestListTubes",
      [@protocol.ListTubes],
      b"list-tubes\r\n",
      b"OK 14\r\n---\n- default\n\r\n",
      [@protocol.Reply::Ok(b"---\n- default\n")],
    ),
    (
      "TestPeek",
      [@protocol.Peek(1UL)],
      b"peek 1\r\n",
      b"FOUND 1 1\r\nx\r\n",
      [@protocol.Found(1UL, b"x")],
    ),
    (
      "TestPeekTwice",
      [@protocol.Peek(1UL), @protocol.Peek(1UL)],
      b"peek 1\r\npeek 1\r\n",
      b"FOUND 1 1\r\nx\r\nFOUND 1 1\r\nx\r\n",
      [@protocol.Found(1UL, b"x"), @protocol.Found(1UL, b"x")],
    ),
    (
      "TestRelease",
      [@protocol.Release(1UL, 3U, 2U)],
      b"release 1 3 2\r\n",
      b"RELEASED\r\n",
      [@protocol.Status(@protocol.Released)],
    ),
    (
      "TestStats",
      [@protocol.Stats],
      b"stats\r\n",
      b"OK 10\r\n---\na: ok\n\r\n",
      [@protocol.Reply::Ok(b"---\na: ok\n")],
    ),
    (
      "TestStatsJob",
      [@protocol.StatsJob(1UL)],
      b"stats-job 1\r\n",
      b"OK 10\r\n---\na: ok\n\r\n",
      [@protocol.Reply::Ok(b"---\na: ok\n")],
    ),
    (
      "TestTouch",
      [@protocol.Touch(1UL)],
      b"touch 1\r\n",
      b"TOUCHED\r\n",
      [@protocol.Status(@protocol.Touched)],
    ),
  ]
  for (name, commands, sent, received, expected) in cases {
    let encoded = @buffer.Buffer()
    for command in commands {
      match @protocol.encode(command) {
        Ok(bytes) => encoded.write_bytes(bytes)
        Err(error) => fail("\{name}: \{@debug.to_string(error)}")
      }
    }
    @debug.assert_eq(encoded.to_bytes(), sent, msg=name)
    for split in 0..<=received.length() {
      let decoder = @protocol.Decoder::new()
      @debug.assert_eq(
        decoder.feed(received[:split].to_owned()),
        Ok(()),
        msg=name,
      )
      let replies = drain(decoder)
      @debug.assert_eq(
        decoder.feed(received[split:].to_owned()),
        Ok(()),
        msg=name,
      )
      replies.push_iter(drain(decoder).iter())
      @debug.assert_eq(replies, expected, msg=name)
      @debug.assert_eq(decoder.finish(), Ok(()), msg=name)
    }
  }
  // The Go reference tests interpret these exact YAML payloads as scalars/list.
  @debug.assert_eq(@protocol.parse_tubes(b"---\n- default\n"), Ok(["default"]))
  @debug.assert_eq(@protocol.parse_stats(b"---\na: ok\n"), Ok({ "a": "ok" }))
}

///|
test "pinned Go reference name validation cases reject before sending" {
  // TestNameTooLong, TestNameEmpty, TestNameBadChar.
  for name in [String::make(201, '\u0000'), "", "*"] {
    @debug.assert_eq(
      @protocol.encode(@protocol.Use(name)),
      Err(@protocol.InvalidTube(name)),
    )
  }
}
