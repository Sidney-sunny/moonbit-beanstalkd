import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const pin = JSON.parse(readFileSync(path.join(root, "toolchain.json"), "utf8"));
const evidence = {
  startedAt: new Date().toISOString(),
  platform: process.platform,
  arch: process.arch,
  node: process.versions.node,
  requiredToolchain: pin,
  server: JSON.parse(readFileSync(new URL("beanstalkd-source.json", import.meta.url), "utf8")),
  checks: [],
  complete: false,
};

function run(executable, args, capture = false) {
  console.log(`> ${executable} ${args.join(" ")}`);
  const started = Date.now();
  const result = spawnSync(executable, args, {
    cwd: root,
    windowsHide: true,
    timeout: 240_000,
    encoding: "utf8",
    stdio: capture ? "pipe" : "inherit",
  });
  evidence.checks.push({
    executable, args, exitCode: result.status, signal: result.signal,
    durationMs: Date.now() - started,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${executable} failed: ${result.error?.message || result.stderr || result.status}`);
  }
  if (capture) process.stdout.write(result.stdout);
  return result.stdout;
}

function withServer(executable, args) {
  run(process.execPath, ["scripts/with-beanstalkd.mjs", "--", executable, ...args]);
}

try {
  if (process.versions.node !== pin.node) {
    throw new Error(`Expected Node ${pin.node}, got ${process.versions.node}`);
  }
  evidence.moonVersions = run("moon", ["version", "--all"], true);
  if (!evidence.moonVersions.includes(`moon ${pin.moon} `)
    || !evidence.moonVersions.includes(`moonc ${pin.moonc} `)) {
    throw new Error("MoonBit toolchain differs from toolchain.json");
  }
  evidence.goVersion = run("go", ["version"], true).trim();
  if (pin.go && !evidence.goVersion.includes(`go${pin.go} `)) {
    throw new Error("Go toolchain differs from toolchain.json");
  }
  run("moon", ["fmt", "--check"]);
  for (const target of ["js", "wasm-gc"]) {
    run("moon", ["check", "--target", target, "--deny-warn"]);
    run("moon", ["build", "--target", target, "--deny-warn"]);
    if (target === "js") withServer("moon", ["test", "--target", target, "--deny-warn"]);
    else run("moon", ["test", "--target", target, "--deny-warn"]);
  }
  run(process.execPath, ["--test", "node_tcp/bridge_test.mjs"]);
  run(process.execPath, ["--test", "scripts/runner_test.mjs"]);
  withServer("moon", ["run", "examples/lifecycle", "--target", "js"]);
  withServer(process.execPath, ["interop/run.mjs"]);
  for (const scenario of ["csv-import", "retry-quarantine", "ttr"]) {
    withServer(process.execPath, [`scenarios/${scenario}.mjs`]);
  }
  withServer(process.execPath, ["scripts/downstream-consumer.mjs"]);
  run(process.execPath, ["benchmark/run.mjs"]);
  evidence.complete = true;
} catch (error) {
  evidence.error = error.message;
  console.error(error.message);
  process.exitCode = 1;
} finally {
  evidence.finishedAt = new Date().toISOString();
  mkdirSync(path.join(root, "_build"), { recursive: true });
  writeFileSync(path.join(root, "_build", "verification.json"), JSON.stringify(evidence, null, 2) + "\n");
}
