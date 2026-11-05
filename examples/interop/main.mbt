///|
extern "js" fn env(name : String, fallback : String) -> String =
  #| (name, fallback) => process.env[name] ?? fallback

///|
extern "js" fn fixture() -> Bytes =
  #| () => new Uint8Array(Buffer.from(process.env.BEANSTALKD_INTEROP_HEX, "hex"))

///|
extern "js" fn emit(
  mode : String,
  tube : String,
  id : String,
  body : Bytes,
  deleted : Bool,
) -> Unit =
  #| (mode, tube, id, body, deleted) => console.log(JSON.stringify({
  #|   runtime: "moonbit", mode, tube, id,
  #|   body_hex: Buffer.from(body).toString("hex"),
  #|   deleted, queue_empty: deleted,
  #| }))

///|
async fn main {
  let mode = env("BEANSTALKD_INTEROP_MODE", "")
  let tube = env("BEANSTALKD_INTEROP_TUBE", "")
  let body = fixture()
  let host = env("BEANSTALKD_HOST", "127.0.0.1")
  let port = @string.parse_int(env("BEANSTALKD_PORT", "11300"))
  let client = @node_client.connect(host, port)
  defer client.close()
  assert_eq(client.execute(@protocol.Use(tube)), @protocol.Using(tube))
  match mode {
    "put" => {
      let id = match client.execute(@protocol.Put(0U, 0U, 30U, body)) {
        Inserted(id) => id
        _ => fail("expected INSERTED")
      }
      emit(mode, tube, id.to_string(), body, false)
    }
    "consume" => {
      assert_eq(client.execute(@protocol.Watch(tube)), @protocol.Watching(2UL))
      assert_eq(
        client.execute(@protocol.Ignore("default")),
        @protocol.Watching(1UL),
      )
      let (id, actual) = match
        client.execute(@protocol.ReserveWithTimeout(1U)) {
        Reserved(id, actual) => (id, actual)
        _ => fail("expected RESERVED")
      }
      assert_eq(actual, body)
      assert_eq(client.execute(@protocol.Touch(id)), @protocol.Status(Touched))
      assert_eq(client.execute(@protocol.Delete(id)), @protocol.Status(Deleted))
      assert_eq(
        client.execute(@protocol.ReserveWithTimeout(0U)),
        @protocol.Status(TimedOut),
      )
      emit(mode, tube, id.to_string(), actual, true)
    }
    _ => fail("BEANSTALKD_INTEROP_MODE must be put or consume")
  }
}
