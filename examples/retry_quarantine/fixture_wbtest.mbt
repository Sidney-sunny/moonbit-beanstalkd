///|
test "only explicit retry fixture reaches the simulated handler" {
  assert_eq(
    classify(
      b"{\"task_id\":\"retry-once-v1\",\"kind\":\"retry\",\"failures_before_success\":1}\n",
    ),
    "retry",
  )
  assert_eq(
    classify(
      b"{\"task_id\":\"quarantine-v1\",\"kind\":\"invalid\",\"reason\":\"missing_required_field\"}\n",
    ),
    "invalid",
  )
  assert_false(retry_succeeds(1))
  assert_true(retry_succeeds(2))
  let rejected = try {
    ignore(classify(b"{\"kind\":\"unknown\"}"))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}
