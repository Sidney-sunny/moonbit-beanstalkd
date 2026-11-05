///|
extern "js" fn env(name : String, fallback : String) -> String =
  #| (name, fallback) => process.env[name] ?? fallback

///|
extern "js" fn fixture(name : String) -> Bytes =
  #| name => new Uint8Array(Buffer.from(process.env[name], "hex"))

///|
extern "js" fn emit(
  retry_id : String,
  quarantine_id : String,
  retry_body : Bytes,
  quarantine_body : Bytes,
) -> Unit =
  #| (retryId, quarantineId, retryBody, quarantineBody) => console.log(JSON.stringify({
  #|   scenario: "retry-quarantine", retry_id: retryId, quarantine_id: quarantineId,
  #|   retry_body_hex: Buffer.from(retryBody).toString("hex"),
  #|   quarantine_body_hex: Buffer.from(quarantineBody).toString("hex"),
  #|   release_delay_seconds: 2, delayed_state_observed: true,
  #|   no_early_reserve: true, retry_attempts: 2, retry_deleted: true,
  #|   buried_state_observed: true, peek_preserved_payload: true,
  #|   invalid_executions: 0, kicked_and_rechecked: true, quarantine_deleted: true,
  #|   queue_empty: true,
  #| }))

///|
fn classify(body : Bytes) -> String raise {
  let job = @json.parse(@utf8.decode(body))
  let retry : Json = {
    "task_id": "retry-once-v1",
    "kind": "retry",
    "failures_before_success": 1,
  }
  let invalid : Json = {
    "task_id": "quarantine-v1",
    "kind": "invalid",
    "reason": "missing_required_field",
  }
  if job == retry {
    return "retry"
  }
  if job == invalid {
    return "invalid"
  }
  fail("unknown example fixture; no task is executed")
}

///|
fn retry_succeeds(attempt : Int32) -> Bool {
  attempt > 1
}

///|
async fn job_stats(
  client : @node_client.Client,
  id : UInt64,
) -> Map[String, String] {
  match client.execute(@protocol.StatsJob(id)) {
    Ok(bytes) =>
      match @protocol.parse_stats(bytes) {
        Ok(stats) => stats
        Err(_) => fail("invalid stats-job body")
      }
    _ => fail("expected stats-job reply")
  }
}

///|
async fn reserve_eventually(client : @node_client.Client) -> (UInt64, Bytes) {
  let deadline = @async.now() + 8000L
  while @async.now() < deadline {
    match client.execute(@protocol.ReserveWithTimeout(0U), timeout_ms=1000) {
      Reserved(id, body) => return (id, body)
      Status(TimedOut) => @async.sleep(100)
      _ => fail("unexpected reserve response")
    }
  }
  fail("retry was not observable within eight seconds")
}

///|
async fn main {
  let retry_body = fixture("BEANSTALKD_RETRY_HEX")
  let invalid_body = fixture("BEANSTALKD_QUARANTINE_HEX")
  assert_eq(classify(retry_body), "retry")
  assert_eq(classify(invalid_body), "invalid")
  let tube = env("BEANSTALKD_SCENARIO_TUBE", "")
  let client = @node_client.connect(
    env("BEANSTALKD_HOST", "127.0.0.1"),
    @string.parse_int(env("BEANSTALKD_PORT", "11300")),
  )
  defer client.close()
  assert_eq(client.execute(@protocol.Use(tube)), @protocol.Using(tube))
  assert_eq(client.execute(@protocol.Watch(tube)), @protocol.Watching(2UL))
  assert_eq(
    client.execute(@protocol.Ignore("default")),
    @protocol.Watching(1UL),
  )
  let retry_id = match client.execute(@protocol.Put(0U, 0U, 30U, retry_body)) {
    Inserted(id) => id
    _ => fail("expected INSERTED retry")
  }
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Reserved(retry_id, retry_body),
  )
  assert_false(retry_succeeds(1))
  assert_eq(
    client.execute(@protocol.Release(retry_id, 0U, 2U)),
    @protocol.Status(Released),
  )
  let delayed = job_stats(client, retry_id)
  assert_eq(delayed.get("state"), Some("delayed"))
  assert_eq(delayed.get("releases"), Some("1"))
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  let (actual_id, actual_body) = reserve_eventually(client)
  assert_eq(actual_id, retry_id)
  assert_eq(actual_body, retry_body)
  assert_true(retry_succeeds(2))
  assert_eq(job_stats(client, retry_id).get("reserves"), Some("2"))
  assert_eq(
    client.execute(@protocol.Delete(retry_id)),
    @protocol.Status(Deleted),
  )

  let invalid_id = match
    client.execute(@protocol.Put(0U, 0U, 30U, invalid_body)) {
    Inserted(id) => id
    _ => fail("expected INSERTED quarantine fixture")
  }
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Reserved(invalid_id, invalid_body),
  )
  assert_eq(classify(invalid_body), "invalid")
  // Validation rejects this fixture before business execution. It is buried
  // for inspection, then explicitly kicked and rejected again before deletion.
  assert_eq(
    client.execute(@protocol.Bury(invalid_id, 0U)),
    @protocol.Status(Buried),
  )
  assert_eq(job_stats(client, invalid_id).get("state"), Some("buried"))
  assert_eq(
    client.execute(@protocol.PeekBuried),
    @protocol.Found(invalid_id, invalid_body),
  )
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  assert_eq(
    client.execute(@protocol.KickJob(invalid_id)),
    @protocol.Status(Kicked),
  )
  assert_eq(
    client.execute(@protocol.PeekReady),
    @protocol.Found(invalid_id, invalid_body),
  )
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Reserved(invalid_id, invalid_body),
  )
  assert_eq(classify(invalid_body), "invalid")
  assert_eq(
    client.execute(@protocol.Delete(invalid_id)),
    @protocol.Status(Deleted),
  )
  assert_eq(
    client.execute(@protocol.Peek(invalid_id)),
    @protocol.Status(NotFound),
  )
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  emit(retry_id.to_string(), invalid_id.to_string(), actual_body, invalid_body)
}
