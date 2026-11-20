///|
extern "js" fn env(name : String, fallback : String) -> String =
  #| (name, fallback) => process.env[name] ?? fallback

///|
extern "js" fn unique_tube() -> String =
  #| () => `moonbit-lifecycle-${process.pid}-${Date.now()}`

///|
fn assert_job(reply : @protocol.Reply, id : UInt64, body : Bytes) -> Unit raise {
  match reply {
    Reserved(actual_id, actual_body) | Found(actual_id, actual_body) => {
      assert_eq(actual_id, id)
      assert_eq(actual_body, body)
    }
    _ => fail("expected a reserved/found job")
  }
}

///|
async fn wait_for_reservation(
  producer : @node_client.Client,
  tube : String,
) -> Unit {
  @async.with_timeout(2000, () => {
    while true {
      match producer.stats_tube(tube, timeout_ms=500) {
        Some(stats) if stats.get("current-waiting") == Some("1") => break
        _ => @async.sleep(10)
      }
    }
  })
}

///|
async fn reservation_controls(
  producer : @node_client.Client,
  host : String,
  port : Int32,
  tube : String,
  body : Bytes,
) -> Unit {
  let worker = @node_client.connect(host, port)
  defer worker.close()
  assert_eq(worker.watch(tube), 2UL)
  assert_eq(worker.ignore_tube("default"), @node_client.Watching(1UL))

  @async.with_task_group(group => {
    let reservation = group.spawn(() => worker.reserve_blocking())
    wait_for_reservation(producer, tube)
    let id = match producer.put(body, ttr=30U) {
      Inserted(id) => id
      _ => fail("expected a ready job")
    }
    assert_eq(reservation.wait(), @node_client.Reserved({ id, body, }))
    assert_eq(producer.reserve_job(id), None)
    assert_eq(worker.release(id), @node_client.Released)
    assert_true(producer.pause_tube(tube, 30U))
    assert_eq(worker.reserve(), @node_client.TimedOut)
    assert_eq(producer.peek_ready(), Some({ id, body, }))
    assert_true(producer.pause_tube(tube, 0U))
    assert_eq(worker.reserve(), @node_client.Reserved({ id, body, }))

    assert_eq(worker.release(id, delay=30U), @node_client.Released)
    assert_eq(producer.peek_delayed(), Some({ id, body, }))
    assert_eq(producer.reserve_job(id), Some({ id, body, }))
    assert_true(producer.delete(id))
    assert_eq(worker.reserve(), @node_client.TimedOut)
  })
  println(
    "reservation controls ok: blocking wait, pause, resume, and reserve by ID",
  )
}

///|
async fn main {
  let host = env("BEANSTALKD_HOST", "127.0.0.1")
  let port = @string.parse_int(env("BEANSTALKD_PORT", "11300"))
  let client = @node_client.connect(host, port)
  defer client.close()
  let tube = unique_tube()
  assert_eq(client.execute(@protocol.Use(tube)), @protocol.Using(tube))
  assert_eq(client.execute(@protocol.Watch(tube)), @protocol.Watching(2UL))
  assert_eq(
    client.execute(@protocol.Ignore("default")),
    @protocol.Watching(1UL),
  )
  let body = b"moon\x00\r\nbean\xff"
  let id = match client.execute(@protocol.Put(0U, 0U, 30U, body)) {
    Inserted(id) => id
    _ => fail("expected INSERTED")
  }
  assert_job(client.execute(@protocol.ReserveWithTimeout(1U)), id, body)
  assert_eq(client.execute(@protocol.Touch(id)), @protocol.Status(Touched))
  assert_eq(
    client.execute(@protocol.Release(id, 0U, 0U)),
    @protocol.Status(Released),
  )
  assert_job(client.execute(@protocol.ReserveWithTimeout(1U)), id, body)
  assert_eq(client.execute(@protocol.Bury(id, 0U)), @protocol.Status(Buried))
  assert_job(client.execute(@protocol.PeekBuried), id, body)
  assert_eq(client.execute(@protocol.KickJob(id)), @protocol.Status(Kicked))
  assert_job(client.execute(@protocol.ReserveWithTimeout(1U)), id, body)
  assert_eq(client.execute(@protocol.Delete(id)), @protocol.Status(Deleted))
  assert_eq(client.execute(@protocol.Peek(id)), @protocol.Status(NotFound))
  assert_eq(
    client.execute(@protocol.ReserveWithTimeout(0U)),
    @protocol.Status(TimedOut),
  )
  assert_true(client.is_open())
  match client.execute(@protocol.StatsTube(tube)) {
    Ok(bytes) =>
      match @protocol.parse_stats(bytes) {
        Ok(stats) => {
          assert_eq(stats.get("current-jobs-ready"), Some("0"))
          assert_eq(stats.get("current-jobs-buried"), Some("0"))
        }
        Err(_) => fail("invalid stats document")
      }
    _ => fail("expected stats body")
  }
  reservation_controls(client, host, port, tube, body)
  println(
    "lifecycle ok: binary put/reserve/touch/release/bury/peek/kick/delete; queue empty",
  )
}
