///|
test "CSV subset preserves rows and rejects unsupported or ambiguous input" {
  assert_eq(parse_csv("id,name,task\n1,Ada,send_receipt\n"), [
    b"1,Ada,send_receipt",
  ])
  for
    invalid in [
      "id,name,task\n", "id,name,task\n1,Ada,send_receipt", "id,name,task\r\n1,Ada,send_receipt\r\n",
      "id,name,task\n1,\"Ada\",send_receipt\n", "id,name,task\n1,,send_receipt\n",
      "id,name,task\n1,Ada,send_receipt,extra\n", "id,name,task\n0,Ada,send_receipt\n",
      "id,name,task\n1,Ada,send_receipt\n1,Lin,refresh_report\n", "id,name,task\n01,Ada,send_receipt\n1,Lin,refresh_report\n",
      "id,name,task\n+1,Ada,send_receipt\n",
    ] {
    let rejected = try {
      ignore(parse_csv(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "CSV task JSON permits only the fixed fixture path and task identifier" {
  assert_eq(parse_job(fixture_job()), "scenarios/fixtures/import.csv")
  for
    invalid in [
      b"{}", b"{\"csv_path\":\"../secrets.csv\",\"task_id\":\"csv-import-fixture-v1\"}",
      b"{\"csv_path\":\"scenarios/fixtures/import.csv\",\"task_id\":\"unexpected\"}",
    ] {
    let rejected = try {
      ignore(parse_job(invalid))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
