import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { binary, build, run } from "./process.mjs";

const fixtureHex = readFileSync(new URL("fixtures/ttr.hex", import.meta.url), "utf8").trim();
assert.match(fixtureHex, /^(?:[0-9a-f]{2})+$/);
const fixture = Buffer.from(fixtureHex, "hex");
const sha256 = createHash("sha256").update(fixture).digest("hex");
assert.equal(sha256, "75948f6703d75e2f405778460216ad89c9d7178b797c2ec2f0a89d5524c27fb8");
await build("ttr");
const output = await run(process.execPath, [binary("ttr")], {
  timeoutMs: 25_000,
  env: {
    ...process.env,
    BEANSTALKD_SCENARIO_TUBE: `moonbit-ttr-${randomUUID()}`,
    BEANSTALKD_TTR_HEX: fixtureHex,
  },
});
const result = JSON.parse(output);
assert.equal(result.scenario, "ttr");
assert.match(result.id, /^[0-9]+$/);
assert.equal(result.body_hex, fixtureHex);
assert.equal(result.ttr_seconds, 6);
assert.ok(BigInt(result.time_left_after_touch) > BigInt(result.time_left_before_touch));
assert.ok(BigInt(result.held_observed_after_ms) > 6000n);
assert.ok(BigInt(result.expiry_observed_after_ms) > BigInt(result.held_observed_after_ms));
assert.equal(result.timeout_count, 1);
assert.equal(result.reserves, 2);
for (const field of ["independent_connections", "held_beyond_original_ttr", "eventual_expiry_observed", "same_job_rereserved", "previous_owner_touch_rejected", "deleted", "queue_empty"]) {
  assert.equal(result[field], true, field);
}
console.log(JSON.stringify({ result: "ttr ok", fixture_sha256: sha256, ...result }, null, 2));
