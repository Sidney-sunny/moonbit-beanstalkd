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
  println(
    "lifecycle ok: binary put/reserve/touch/release/bury/peek/kick/delete; queue empty",
  )
}
