import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { binary, build, run } from "./process.mjs";

const retry = readFileSync(new URL("fixtures/retry.json", import.meta.url));
const quarantine = readFileSync(new URL("fixtures/quarantine.json", import.meta.url));
const hash = bytes => createHash("sha256").update(bytes).digest("hex");
assert.equal(hash(retry), "a7efc2dbf67a5639cb729667f7677b4a52910dbebcc22fe196c14fffe56a223a");
assert.equal(hash(quarantine), "f4ce833e25498335a3ca364a3e1691aef400d108ee2bde8c5ebde8a2e1b9ca7e");
await build("retry_quarantine");
const stdout = await run(process.execPath, [binary("retry_quarantine")], {
  env: {
    ...process.env,
    BEANSTALKD_SCENARIO_TUBE: `moonbit-retry-${randomUUID()}`,
    BEANSTALKD_RETRY_HEX: retry.toString("hex"),
    BEANSTALKD_QUARANTINE_HEX: quarantine.toString("hex"),
  },
});
const result = JSON.parse(stdout);
assert.equal(result.scenario, "retry-quarantine");
assert.match(result.retry_id, /^[0-9]+$/);
assert.match(result.quarantine_id, /^[0-9]+$/);
assert.notEqual(result.retry_id, result.quarantine_id);
assert.equal(result.retry_body_hex, retry.toString("hex"));
assert.equal(result.quarantine_body_hex, quarantine.toString("hex"));
assert.equal(result.release_delay_seconds, 2);
assert.equal(result.retry_attempts, 2);
assert.equal(result.invalid_executions, 0);
for (const field of ["delayed_state_observed", "no_early_reserve", "retry_deleted", "buried_state_observed", "peek_preserved_payload", "kicked_and_rechecked", "quarantine_deleted", "queue_empty"]) {
  assert.equal(result[field], true, field);
}
console.log(JSON.stringify({
  result: "retry-quarantine ok", retry_sha256: hash(retry), quarantine_sha256: hash(quarantine),
  ...result,
}, null, 2));
