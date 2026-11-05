import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, statSync, symlinkSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { readPackageZip } from "../packaging/zip.mjs";

const root = realpathSync(fileURLToPath(new URL("../", import.meta.url)));
const base = path.join(root, "_build", "downstream");
mkdirSync(base, { recursive: true });
const work = mkdtempSync(path.join(base, "run-"));
const extracted = path.join(work, "library");
const consumer = path.join(work, "consumer");
const evidence = {
  kind: "local-package-workspace-consumer",
  registryInstallVerified: false,
  publicationPerformed: false,
  startedAt: new Date().toISOString(),
  directory: path.relative(root, work).replaceAll("\\", "/"),
  node: process.versions.node,
  complete: false,
};

function run(executable, args, env = process.env) {
  const result = spawnSync(executable, args, {
    cwd: root, env, encoding: "utf8", windowsHide: true, timeout: 120_000,
  });
  if (result.error || result.status !== 0) throw new Error(`${executable} failed: ${result.error?.message || result.stderr || result.stdout}`);
  return result.stdout;
}

function isolatedEnvironment() {
  const executable = process.platform === "win32" ? "moon.exe" : "moon";
  const selected = process.env.MOON_HOME || (process.env.PATH || "").split(path.delimiter)
    .filter(Boolean).map(dir => path.join(dir, executable))
    .find(filename => existsSync(filename) && statSync(filename).isFile());
  assert.ok(selected, "MoonBit toolchain unavailable");
  const installed = process.env.MOON_HOME ? realpathSync(selected) : path.dirname(path.dirname(realpathSync(selected)));
  const home = path.join(work, "moon-home");
  mkdirSync(home);
  for (const directory of ["bin", "lib"]) {
    symlinkSync(path.join(installed, directory), path.join(home, directory), process.platform === "win32" ? "junction" : "dir");
  }
  const env = { ...process.env };
  for (const name of Object.keys(env)) {
    if (/^MOON(?:CAKES)?_.*(?:TOKEN|AUTH|CREDENTIAL|USER)/i.test(name) || /^(GH_TOKEN|GITHUB_TOKEN|GH_CONFIG_DIR)$/.test(name)) delete env[name];
  }
  Object.assign(env, {
    MOON_HOME: home,
    MOON_TOOLCHAIN_ROOT: home,
    MOON_CORE_OVERRIDE: path.join(home, "lib", "core"),
    MOON_DEP_CACHE: path.join(home, "cache", "deps"),
    MOON_BUILD_CACHE: path.join(home, "cache", "build"),
  });
  return { executable: path.join(home, "bin", executable), env };
}

try {
  const isolated = isolatedEnvironment();
  run(isolated.executable, ["package", "--target-dir", path.join(work, "archive")], isolated.env);
  const manifest = readFileSync(path.join(root, "moon.mod"), "utf8");
  const moduleName = manifest.match(/^name\s*=\s*"([^"]+)"/m)?.[1];
  const version = manifest.match(/^version\s*=\s*"([^"]+)"/m)?.[1];
  assert.ok(moduleName && version, "module metadata missing");
  const archive = path.join(work, "archive", "publish", `${moduleName.replaceAll("/", "-")}-${version}.zip`);
  const archiveBytes = readFileSync(archive);
  const entries = readPackageZip(archiveBytes);
  for (const name of entries.keys()) {
    const segments = name.split("/");
    assert.ok(!segments.some(segment => ["_build", ".private", ".moon", ".git", "node_modules"].includes(segment)), `private/build path packaged: ${name}`);
    assert.ok(!segments.some(segment => /^\.env(?:\.|$)/.test(segment) && segment !== ".env.example"), `environment file packaged: ${name}`);
    assert.ok(!/^(?:credentials|tokens?)\.(?:json|toml|yaml|yml)$/.test(path.posix.basename(name)), `credential file packaged: ${name}`);
  }
  for (const required of ["moon.mod", "LICENSE", "protocol/moon.pkg", "node_client/moon.pkg", "node_tcp/transport_ffi.mbt"]) {
    assert.ok(entries.has(required), `public package file missing: ${required}`);
  }
  mkdirSync(extracted);
  for (const [name, bytes] of entries) {
    const target = path.join(extracted, ...name.split("/"));
    if (name.endsWith("/")) mkdirSync(target, { recursive: true });
    else {
      mkdirSync(path.dirname(target), { recursive: true });
      writeFileSync(target, bytes);
    }
  }
  assert.equal(readFileSync(path.join(extracted, "moon.mod"), "utf8"), manifest);
  mkdirSync(consumer);
  writeFileSync(path.join(work, "moon.work"), 'members = ["library", "consumer"]\n');
  writeFileSync(path.join(consumer, "moon.mod"), `name = "local/package_consumer"\n\nversion = "0.0.0"\n\nimport { "${moduleName}@${version}" }\n\npreferred_target = "js"\n`);
  writeFileSync(path.join(consumer, "moon.pkg"), readFileSync(path.join(root, "packaging", "consumer-moon.pkg.txt")));
  writeFileSync(path.join(consumer, "main.mbt"), readFileSync(path.join(root, "packaging", "consumer-main.mbt.txt")));
  evidence.moonVersions = run(isolated.executable, ["version", "--all"], isolated.env);
  run(isolated.executable, ["-C", consumer, "build", "--target", "js", "--deny-warn", "--frozen"], isolated.env);
  const output = run(isolated.executable, ["-C", consumer, "run", ".", "--target", "js", "--frozen"], isolated.env).trim();
  assert.match(output, /local package consumer ok/);
  Object.assign(evidence, {
    moduleName, version, archiveSha256: createHash("sha256").update(archiveBytes).digest("hex"),
    archiveBytes: archiveBytes.length, entries: entries.size,
    excludedPrivateAndBuildPaths: true, dependencySource: "extracted local archive via isolated moon.work",
    consumerOutput: output, complete: true,
  });
  console.log(JSON.stringify(evidence, null, 2));
} catch (error) {
  evidence.error = error.message;
  console.error(error.message);
  process.exitCode = 1;
} finally {
  evidence.finishedAt = new Date().toISOString();
  writeFileSync(path.join(base, "result.json"), JSON.stringify(evidence, null, 2) + "\n");
}
