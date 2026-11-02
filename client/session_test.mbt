///|
test "session serializes requests and updates tube state only after reply" {
  let session = @client.Session::new()
  assert_eq(session.used_tube(), "default")
  assert_eq(session.begin(@protocol.Use("imports")), Ok(b"use imports\r\n"))
  assert_eq(session.begin(@protocol.Stats), Err(@client.Busy))
  assert_eq(session.used_tube(), "default")
  assert_eq(session.feed(b"USING imp"), Ok(None))
  assert_eq(session.feed(b"orts\r\n"), Ok(Some(@protocol.Using("imports"))))
  assert_eq(session.used_tube(), "imports")
  assert_false(session.is_busy())
  assert_true(session.is_usable())
}

///|
test "complete server timeout keeps framing and connection usable" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.ReserveWithTimeout(0U)))
  assert_eq(
    session.feed(b"TIMED_OUT\r\n"),
    Ok(Some(@protocol.Status(TimedOut))),
  )
  assert_true(session.is_usable())
  assert_eq(session.begin(@protocol.Watch("imports")), Ok(b"watch imports\r\n"))
  assert_eq(session.feed(b"WATCHING 2\r\n"), Ok(Some(@protocol.Watching(2UL))))
  assert_eq(session.watching_count(), 2UL)
}

///|
test "mismatched complete reply invalidates session and refuses publication" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.Delete(7UL)))
  assert_eq(session.feed(b"INSERTED 7\r\n"), Err(@client.UnexpectedReply))
  assert_false(session.is_usable())
  assert_eq(
    session.begin(@protocol.Put(0U, 0U, 30U, b"x")),
    Err(@client.Closed),
  )
}

///|
test "extra response bytes are rejected instead of attributed to a later command" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.Delete(7UL)))
  assert_eq(
    session.feed(b"DELETED\r\nINSERTED 8\r\n"),
    Err(@client.UnsolicitedData),
  )
  assert_false(session.is_usable())
}

///|
test "local validation failures do not consume the connection" {
  let session = @client.Session::new()
  assert_eq(
    session.begin(@protocol.Use("bad\r\n")),
    Err(@client.Protocol(InvalidTube("bad\r\n"))),
  )
  assert_true(session.is_usable())
  assert_false(session.is_busy())
  assert_eq(session.begin(@protocol.ListTubeUsed), Ok(b"list-tube-used\r\n"))
}

///|
test "EOF without response is an incomplete exchange and cannot replay" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.Put(0U, 0U, 30U, b"x")))
  assert_eq(session.finish(), Err(@client.Protocol(Truncated)))
  assert_false(session.is_usable())
}

///|
test "binary reserved payload survives fragmented session feeding" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.ReserveWithTimeout(1U)))
  assert_eq(session.feed(b"RESERVED 18446744073709551615 4\r\na\x00"), Ok(None))
  assert_eq(
    session.feed(b"\r\n\r\n"),
    Ok(Some(@protocol.Reserved(18446744073709551615UL, b"a\x00\r\n"))),
  )
}

///|
test "peek response must identify the requested job" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.Peek(42UL)))
  assert_eq(session.feed(b"FOUND 43 1\r\nx\r\n"), Err(@client.UnexpectedReply))
  assert_false(session.is_usable())
}

///|
test "kick result cannot exceed the requested bound" {
  let session = @client.Session::new()
  ignore(session.begin(@protocol.Kick(2U)))
  assert_eq(session.feed(b"KICKED 3\r\n"), Err(@client.UnexpectedReply))
  assert_false(session.is_usable())
}

///|
test "invalid decoder limits reject publication before a request becomes busy" {
  let invalid_sessions = [
    @client.Session::new(max_header=0),
    @client.Session::new(max_header=-1),
    @client.Session::new(max_body=-1),
    @client.Session::new(max_buffer=0),
    @client.Session::new(max_buffer=-1),
  ]
  for session in invalid_sessions {
    assert_eq(
      session.begin(@protocol.Put(0U, 0U, 30U, b"must not be sent")),
      Err(@client.Protocol(InvalidLimits)),
    )
    assert_false(session.is_busy())
    assert_false(session.is_usable())
    assert_eq(session.begin(@protocol.ListTubeUsed), Err(@client.Closed))
    assert_false(session.is_busy())
  }
}
