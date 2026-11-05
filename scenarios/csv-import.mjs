import assert from "node:assert/strict";
import { createHash, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { binary, build, run } from "./process.mjs";

const bytes = readFileSync(new URL("fixtures/import.csv", import.meta.url));
const fixtureSha256 = createHash("sha256").update(bytes).digest("hex");
assert.equal(fixtureSha256, "6aaad27f2821ed1ada0fff0bac27ad99aca2f6cc6ad4e9e90faa842ff9482b1b");
const fixture = bytes.toString("utf8");
const rows = fixture.trimEnd().split("\n").slice(1);
const tube = `moonbit-csv-${randomUUID()}`;
await build("csv_import");

async function invoke(mode) {
  const stdout = await run(process.execPath, [binary("csv_import")], {
    env: {
      ...process.env,
      BEANSTALKD_SCENARIO_MODE: mode,
      BEANSTALKD_SCENARIO_TUBE: tube,
    },
  });
  const result = JSON.parse(stdout);
  assert.equal(result.scenario, "csv-import");
  assert.equal(result.mode, mode);
  assert.equal(result.tube, tube);
  assert.match(result.id, /^[0-9]+$/);
  assert.deepEqual(JSON.parse(Buffer.from(result.job_body_hex, "hex").toString("utf8")), {
    csv_path: "scenarios/fixtures/import.csv", task_id: "csv-import-fixture-v1",
  });
  return result;
}

const producer = await invoke("producer");
const worker = await invoke("worker");
assert.notEqual(producer.pid, worker.pid, "producer and worker must be separate processes");
assert.equal(worker.id, producer.id);
assert.equal(worker.job_body_hex, producer.job_body_hex);
assert.equal(worker.csv_hex, bytes.toString("hex"));
assert.equal(worker.rows, rows.length);
assert.equal(worker.deleted, true);
assert.equal(worker.queue_empty, true);
console.log(JSON.stringify({
  result: "csv-import ok", fixture_sha256: fixtureSha256,
  rows: rows.length, id: worker.id, separate_processes: true,
  exact_payloads: true, deleted: worker.deleted, queue_empty: true,
}, null, 2));
