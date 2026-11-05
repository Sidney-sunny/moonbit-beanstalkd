///|
extern "js" fn env(name : String, fallback : String) -> String =
  #| (name, fallback) => process.env[name] ?? fallback

///|
extern "js" fn fixture() -> Bytes =
  #| () => new Uint8Array(Buffer.from(process.env.BEANSTALKD_TTR_HEX, "hex"))

///|
extern "js" fn emit(
  id : String,
  body : Bytes,
  before : String,
  refreshed : String,
  held_ms : String,
  expired_ms : String,
) -> Unit =
  #| (id, body, before, refreshed, heldMs, expiredMs) => console.log(JSON.stringify({
  #|   scenario: "ttr", id, body_hex: Buffer.from(body).toString("hex"),
  #|   ttr_seconds: 6, time_left_before_touch: before, time_left_after_touch: refreshed,
  #|   held_observed_after_ms: heldMs, expiry_observed_after_ms: expiredMs,
  #|   independent_connections: true, held_beyond_original_ttr: true,
  #|   eventual_expiry_observed: true, same_job_rereserved: true,
  #|   timeout_count: 1, reserves: 2, previous_owner_touch_rejected: true,
  #|   deleted: true, queue_empty: true,
  #| }))

///|
async fn stats(
  client : @node_client.Client,
  id : UInt64,
) -> Map[String, String] {
  match client.execute(@protocol.StatsJob(id)) {
    Ok(body) =>
      match @protocol.parse_stats(body) {
        Ok(values) => values
        Err(_) => fail("malformed stats-job document")
      }
    _ => fail("expected stats-job reply")
  }
}

///|
fn field(values : Map[String, String], key : String) -> String raise {
  match values.get(key) {
    Some(value) => value
    None => fail("missing stats field: \{key}")
  }
}

///|
async fn watch(client : @node_client.Client, tube : String) -> Unit {
  assert_eq(client.execute(@protocol.Watch(tube)), @protocol.Watching(2UL))
  assert_eq(
    client.execute(@protocol.Ignore("default")),
    @protocol.Watching(1UL),
  )
}

///|
async fn reserve_after_expiry(
  client : @node_client.Client,
  expected_id : UInt64,
) -> (UInt64, Bytes) {
  let deadline = @async.now() + 8000L
  while @async.now() < deadline {
    match client.execute(@protocol.ReserveWithTimeout(1U), timeout_ms=2500) {
      Reserved(id, body) => return (id, body)
      Status(TimedOut) => ()
      _ => fail("unexpected observer reserve reply")
    }
  }
  let current = stats(client, expected_id)
  fail(
    "job did not expire: state=\{field(current, "state")}, time-left=\{field(current, "time-left")}, timeouts=\{field(current, "timeouts")}",
  )
}

///|
async fn main {
  let host = env("BEANSTALKD_HOST", "127.0.0.1")
  let port = @string.parse_int(env("BEANSTALKD_PORT", "11300"))
  let tube = env("BEANSTALKD_SCENARIO_TUBE", "")
  let owner = @node_client.connect(host, port)
  defer owner.close()
  // A separately connected observer cannot reserve another connection's job.
  let observer = @node_client.connect(host, port)
  defer observer.close()
  assert_eq(owner.execute(@protocol.Use(tube)), @protocol.Using(tube))
  watch(owner, tube)
  watch(observer, tube)
  let body = fixture()
  let id = match owner.execute(@protocol.Put(0U, 0U, 6U, body)) {
    Inserted(id) => id
    _ => fail("expected INSERTED")
  }
  assert_eq(
    owner.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Reserved(id, body),
  )
  let reserved_at = @async.now()
  assert_eq(
    observer.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  @async.sleep(3500)
  let before = field(stats(owner, id), "time-left")
  assert_eq(owner.execute(@protocol.Touch(id)), @protocol.Status(Touched))
  let after = field(stats(owner, id), "time-left")
  assert_true(@string.parse_uint64(after) > @string.parse_uint64(before))
  @async.sleep(3000)
  // The original six-second reservation window has passed with a safety
  // margin; state and ownership, rather than exact expiry time, are asserted.
  assert_true(@async.now() - reserved_at > 6000L)
  let retained = stats(owner, id)
  let held_ms = @async.now() - reserved_at
  assert_eq(retained.get("state"), Some("reserved"))
  assert_eq(retained.get("timeouts"), Some("0"))
  assert_eq(
    observer.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )

  // Stop touching and let the server make the expiry observable. Polling has
  // an eight-second deadline; no assertion requires an exact timing boundary.
  let (actual_id, actual_body) = reserve_after_expiry(observer, id)
  let expired_ms = @async.now() - reserved_at
  assert_eq(actual_id, id)
  assert_eq(actual_body, body)
  let expired = stats(observer, id)
  assert_eq(expired.get("state"), Some("reserved"))
  assert_eq(expired.get("timeouts"), Some("1"))
  assert_eq(expired.get("reserves"), Some("2"))
  assert_eq(owner.execute(@protocol.Touch(id)), @protocol.Status(NotFound))
  assert_eq(observer.execute(@protocol.Delete(id)), @protocol.Status(Deleted))
  assert_eq(owner.execute(@protocol.Peek(id)), @protocol.Status(NotFound))
  assert_eq(
    observer.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  emit(
    id.to_string(),
    actual_body,
    before,
    after,
    held_ms.to_string(),
    expired_ms.to_string(),
  )
}
