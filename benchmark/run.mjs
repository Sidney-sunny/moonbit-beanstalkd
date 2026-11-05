import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const fixtureHex = readFileSync(new URL("body.hex", import.meta.url), "utf8").trim();
assert.match(fixtureHex, /^(?:[0-9a-f]{2})+$/);
const fixture = Buffer.from(fixtureHex, "hex");
const iterations = Number(process.env.BEANSTALKD_BENCH_ITERATIONS || 20000);
const warmup = Number(process.env.BEANSTALKD_BENCH_WARMUP ?? 2000);
assert.ok(Number.isSafeInteger(iterations) && iterations > 0 && iterations <= 100000, "iterations must be 1..100000");
assert.ok(Number.isSafeInteger(warmup) && warmup >= 0 && warmup <= 20000, "warmup must be 0..20000");

function run(executable, args, env = process.env) {
  const result = spawnSync(executable, args, {
    cwd: root, env, windowsHide: true, encoding: "utf8", timeout: 30_000,
  });
  if (result.error || result.status !== 0) throw new Error(`${executable} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout.trim();
}

const moonVersions = run("moon", ["version", "--all"]);
run("moon", ["build", "examples/benchmark", "--target", "js", "--release", "--deny-warn"]);
const sample = JSON.parse(run(process.execPath, [
  path.join(root, "_build", "js", "release", "build", "examples", "benchmark", "benchmark.js"),
], {
  ...process.env,
  BEANSTALKD_BENCH_ITERATIONS: String(iterations),
  BEANSTALKD_BENCH_WARMUP: String(warmup),
  BEANSTALKD_BENCH_BODY_HEX: fixtureHex,
}));
assert.equal(sample.body_hex, fixtureHex);
assert.equal(sample.iterations, iterations);
assert.equal(sample.warmup, warmup);
assert.equal(sample.checksum, (iterations + warmup) * (sample.encoded_bytes + fixture.length));

function measurement(milliseconds) {
  assert.ok(Number.isFinite(milliseconds) && milliseconds > 0, "invalid monotonic duration");
  return {
    totalMs: milliseconds,
    nanosecondsPerOperation: milliseconds * 1_000_000 / iterations,
    operationsPerSecond: iterations * 1000 / milliseconds,
  };
}

const result = {
  kind: "local-js-protocol-baseline",
  measuredAt: new Date().toISOString(),
  disclaimer: "Local single-process baseline with allocation and reply validation; no TCP throughput or Go parity claim.",
  toolchain: { moon: moonVersions, node: process.versions.node },
  host: { platform: process.platform, arch: process.arch, cpu: os.cpus()[0]?.model },
  dataset: {
    file: "benchmark/body.hex", sha256: createHash("sha256").update(fixture).digest("hex"),
    bodyBytes: fixture.length, encodedCommandBytes: sample.encoded_bytes, replyBytes: sample.reply_bytes,
  },
  iterations, warmup, buildMode: "release", checksum: sample.checksum,
  encodePut: measurement(sample.encode_ms),
  decodeReserved: measurement(sample.decode_ms),
  methodology: "Sequential PUT encoding; new bounded decoder per whole-buffer RESERVED reply; UInt64 and exact body assertions included. Warmup excluded from measurements.",
};
mkdirSync(path.join(root, "_build"), { recursive: true });
writeFileSync(path.join(root, "_build", "benchmark.json"), JSON.stringify(result, null, 2) + "\n");
console.log(JSON.stringify(result, null, 2));
