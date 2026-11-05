///|
extern "js" fn env(name : String, fallback : String) -> String =
  #| (name, fallback) => process.env[name] ?? fallback

///|
extern "js" fn emit(
  mode : String,
  tube : String,
  id : String,
  job_body : Bytes,
  csv_body : Bytes,
  rows : Int32,
  queue_empty : Bool,
) -> Unit =
  #| (mode, tube, id, jobBody, csvBody, rows, queueEmpty) => console.log(JSON.stringify({
  #|   scenario: "csv-import", mode, tube, pid: process.pid,
  #|   id, rows, job_body_hex: Buffer.from(jobBody).toString("hex"),
  #|   csv_hex: Buffer.from(csvBody).toString("hex"),
  #|   deleted: mode === "worker", queue_empty: queueEmpty,
  #| }))

///|
extern "js" fn read_fixture(path : String) -> String =
  #| path => process.getBuiltinModule("node:fs").readFileSync(path, "utf8")

///|
fn fixture_job() -> Bytes {
  let job : Json = {
    "csv_path": "scenarios/fixtures/import.csv",
    "task_id": "csv-import-fixture-v1",
  }
  @utf8.encode(job.stringify())
}

///|
fn parse_job(body : Bytes) -> String raise {
  match @json.parse(@utf8.decode(body)) {
    Object({ "csv_path": String(path), "task_id": String(task_id), .. }) => {
      if path != "scenarios/fixtures/import.csv" ||
        task_id != "csv-import-fixture-v1" {
        fail(
          "CSV task must refer to the fixed allowlisted fixture and task identifier",
        )
      }
      path
    }
    _ => fail("expected a JSON job with csv_path and task_id")
  }
}

// This example intentionally supports a documented CSV subset rather than
// implying full RFC 4180 parsing: ASCII, LF, exact header, three plain fields.

///|
fn parse_csv(text : String) -> Array[Bytes] raise {
  let bytes = @utf8.encode(text)
  for byte in bytes {
    if byte != b'\n' && (byte < b' ' || byte > b'~' || byte == b'"') {
      fail("CSV requires printable ASCII without quotes and LF line endings")
    }
  }
  if !bytes.has_suffix(b"\n") {
    fail("CSV requires a final LF")
  }
  let lines = text.split("\n").map(fn(line) { line.to_owned() }).collect()
  if lines.length() < 3 || lines[0] != "id,name,task" {
    fail("CSV requires id,name,task header and at least one data row")
  }
  let rows = []
  let seen : Map[String, Bool] = Map([])
  for line in lines[1:lines.length() - 1] {
    let fields = line.split(",").map(fn(field) { field.to_owned() }).collect()
    if fields.length() != 3 ||
      fields[0].is_empty() ||
      fields[1].is_empty() ||
      fields[2].is_empty() {
      fail("CSV rows require three nonempty fields")
    }
    for digit in @utf8.encode(fields[0]) {
      if digit < b'0' || digit > b'9' {
        fail("CSV IDs must contain decimal digits only")
      }
    }
    let id = @string.parse_uint64(fields[0])
    let key = id.to_string()
    if id == 0UL || seen.contains(key) {
      fail("CSV IDs must be positive and unique")
    }
    seen[key] = true
    rows.push(@utf8.encode(line))
  }
  rows
}

///|
async fn main {
  let mode = env("BEANSTALKD_SCENARIO_MODE", "")
  let tube = env("BEANSTALKD_SCENARIO_TUBE", "")
  let host = env("BEANSTALKD_HOST", "127.0.0.1")
  let port = @string.parse_int(env("BEANSTALKD_PORT", "11300"))
  let client = @node_client.connect(host, port)
  defer client.close()
  assert_eq(client.execute(@protocol.Use(tube)), @protocol.Using(tube))
  match mode {
    "producer" => {
      let body = fixture_job()
      let id = match client.execute(@protocol.Put(0U, 0U, 30U, body)) {
        Inserted(id) => id
        _ => fail("expected INSERTED")
      }
      emit(mode, tube, id.to_string(), body, b"", 0, false)
    }
    "worker" => {
      assert_eq(client.execute(@protocol.Watch(tube)), @protocol.Watching(2UL))
      assert_eq(
        client.execute(@protocol.Ignore("default")),
        @protocol.Watching(1UL),
      )
      let (id, actual) = match
        client.execute(@protocol.ReserveWithTimeout(1U)) {
        Reserved(id, actual) => (id, actual)
        _ => fail("expected the CSV fixture task")
      }
      assert_eq(actual, fixture_job())
      let fixture_text = read_fixture(parse_job(actual))
      let rows = parse_csv(fixture_text)
      assert_eq(client.execute(@protocol.Delete(id)), @protocol.Status(Deleted))
      assert_eq(
        client.execute(@protocol.ReserveWithTimeout(0U)),
        @protocol.Status(TimedOut),
      )
      emit(
        mode,
        tube,
        id.to_string(),
        actual,
        @utf8.encode(fixture_text),
        rows.length(),
        true,
      )
    }
    _ => fail("BEANSTALKD_SCENARIO_MODE must be producer or worker")
  }
}
