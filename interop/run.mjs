import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { mkdirSync, readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const goDirectory = path.join(root, "interop", "go");
const buildDirectory = path.join(root, "_build", "interop");
const goBinary = path.join(buildDirectory, process.platform === "win32" ? "go-interop.exe" : "go-interop");
const moonBinary = path.join(root, "_build", "js", "debug", "build", "examples", "interop", "interop.js");
const fixtureHex = readFileSync(new URL("fixtures/binary-task.hex", import.meta.url), "utf8").trim();
assert.match(fixtureHex, /^(?:[0-9a-f]{2})+$/);
const fixtureBytes = Buffer.from(fixtureHex, "hex");
const fixtureSha256 = createHash("sha256").update(fixtureBytes).digest("hex");
const provenance = JSON.parse(readFileSync(new URL("provenance.json", import.meta.url), "utf8"));
assert.equal(fixtureBytes.length, provenance.fixture.decoded_bytes);
assert.equal(fixtureSha256, provenance.fixture.decoded_sha256, "fixture checksum differs from provenance");
mkdirSync(buildDirectory, { recursive: true });

function run(executable, args, { cwd = root, env = process.env, timeoutMs = 15_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd, env, windowsHide: true, timeout: timeoutMs,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      if (stdout.length > 1_048_576) child.kill();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      if (stderr.length > 1_048_576) child.kill();
    });
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (code !== 0) {
        reject(new Error(`${executable} failed (${code ?? signal}): ${stderr || stdout}`));
      } else {
        resolve(stdout.trim());
      }
    });
  });
}

function validate(result, runtime, mode, tube) {
  assert.equal(result.runtime, runtime);
  assert.equal(result.mode, mode);
  assert.equal(result.tube, tube);
  assert.match(result.id, /^[0-9]+$/);
  assert.equal(typeof result.id, "string", "job IDs must stay decimal strings");
  assert.equal(result.body_hex, fixtureHex, "binary body differs from fixture");
  if (mode === "consume") {
    assert.equal(result.deleted, true);
    assert.equal(result.queue_empty, true);
  }
  return result;
}

async function invoke(runtime, mode, tube) {
  const env = {
    ...process.env,
    BEANSTALKD_INTEROP_MODE: mode,
    BEANSTALKD_INTEROP_TUBE: tube,
    BEANSTALKD_INTEROP_HEX: fixtureHex,
  };
  const output = runtime === "go"
    ? await run(goBinary, [], { env })
    : await run(process.execPath, [moonBinary], { env });
  return validate(JSON.parse(output), runtime, mode, tube);
}

await Promise.all([
  run("go", ["build", "-mod=readonly", "-trimpath", "-o", goBinary, "."], { cwd: goDirectory, timeoutMs: 120_000 }),
  run("moon", ["build", "--target", "js", "examples/interop"], { timeoutMs: 120_000 }),
]);

const exchanges = [];
for (const [producer, consumer] of [["go", "moonbit"], ["moonbit", "go"]]) {
  const tube = `moonbit-interop-${randomUUID()}`;
  const sent = await invoke(producer, "put", tube);
  const received = await invoke(consumer, "consume", tube);
  assert.equal(received.id, sent.id, "producer and consumer job IDs differ");
  assert.equal(received.body_hex, sent.body_hex);
  exchanges.push({ direction: `${producer}->${consumer}`, id: sent.id, bytes: fixtureBytes.length, deleted: true, queue_empty: true });
}

console.log(JSON.stringify({
  result: "interop ok",
  go_client_revision: "52e4a01c453b3de42105389beb2374f256751064",
  fixture_sha256: fixtureSha256,
  exchanges,
}, null, 2));
