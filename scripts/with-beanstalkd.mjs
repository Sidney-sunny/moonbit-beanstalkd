import { createHash, randomUUID } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { setTimeout as delay } from "node:timers/promises";

const root = fileURLToPath(new URL("../", import.meta.url));
const pin = JSON.parse(readFileSync(new URL("beanstalkd-source.json", import.meta.url), "utf8"));
const cache = path.join(root, "_build", "beanstalkd");
const archive = path.join(cache, `beanstalkd-v${pin.version}.tar.gz`);
const source = path.join(cache, "runner", `beanstalkd-${pin.version}`);
const binary = path.join(source, "beanstalkd");
const isWindows = process.platform === "win32";
const distro = process.env.BEANSTALKD_WSL_DISTRO || "Debian";
const args = process.argv.slice(2);
const separator = args.indexOf("--");
const options = separator < 0 ? args : args.slice(0, separator);
const command = separator < 0 ? [] : args.slice(separator + 1);
const prepareOnly = options.includes("--prepare");
const timeoutMs = Number(process.env.BEANSTALKD_TEST_TIMEOUT_MS || 180_000);
let server;
let child;
let serverExit;
let pidFile;
let serverLog = "";
let stopping = false;

function run(executable, commandArgs, cwd = root) {
  const result = spawnSync(executable, commandArgs, {
    cwd,
    encoding: "utf8",
    timeout: 120_000,
    windowsHide: true,
  });
  if (result.error || result.status !== 0) {
    throw new Error(`${executable} failed: ${result.error?.message || result.stderr || result.stdout}`);
  }
  return result.stdout.trim();
}

function linuxPath(filename) {
  return run("wsl.exe", ["-d", distro, "--exec", "wslpath", "-a", "-u", filename.replaceAll("\\", "/")]);
}

function serverCommand(commandArgs) {
  return isWindows
    ? ["wsl.exe", ["-d", distro, "--exec", ...commandArgs]]
    : [commandArgs[0], commandArgs.slice(1)];
}

async function prepare() {
  mkdirSync(path.dirname(source), { recursive: true });
  if (!existsSync(archive)) {
    const temporary = `${archive}.${randomUUID()}.tmp`;
    try {
      const response = await fetch(pin.url, { signal: AbortSignal.timeout(30_000) });
      if (!response.ok) throw new Error(`Source download returned HTTP ${response.status}`);
      writeFileSync(temporary, Buffer.from(await response.arrayBuffer()));
      const digest = createHash("sha256").update(readFileSync(temporary)).digest("hex");
      if (digest !== pin.sha256) throw new Error(`Source checksum mismatch: ${digest}`);
      renameSync(temporary, archive);
    } finally {
      rmSync(temporary, { force: true });
    }
  }
  const digest = createHash("sha256").update(readFileSync(archive)).digest("hex");
  if (digest !== pin.sha256) throw new Error(`Source checksum mismatch: ${digest}`);
  if (!existsSync(source)) {
    run("tar", ["-xzf", archive, "-C", path.dirname(source)]);
  }
  if (!existsSync(binary)) {
    const [executable, buildArgs] = serverCommand([
      "make", "-j2", "-C", isWindows ? linuxPath(source) : source,
    ]);
    run(executable, buildArgs);
  }
  const [executable, versionArgs] = serverCommand([isWindows ? linuxPath(binary) : binary, "-v"]);
  const version = run(executable, versionArgs);
  if (version !== `beanstalkd ${pin.version}`) throw new Error(`Unexpected server version: ${version}`);
  console.log(`${version}; source sha256 ${pin.sha256}`);
}

async function availablePort() {
  let requested = 0;
  if (process.env.BEANSTALKD_PORT) {
    requested = Number(process.env.BEANSTALKD_PORT);
    if (!Number.isInteger(requested) || requested < 1 || requested > 65535) throw new Error("Invalid BEANSTALKD_PORT");
  }
  return new Promise((resolve, reject) => {
    const listener = net.createServer();
    listener.once("error", (error) => {
      if (requested && error.code === "EADDRINUSE") {
        reject(new Error(`BEANSTALKD_PORT ${requested} is already occupied (EADDRINUSE)`));
      } else {
        reject(error);
      }
    });
    listener.listen({ port: requested, host: "127.0.0.1", exclusive: true }, () => {
      const port = listener.address().port;
      listener.close((error) => error ? reject(error) : resolve(port));
    });
  });
}

function assertServerAlive() {
  if (serverExit !== undefined || server.exitCode !== null || server.signalCode !== null) {
    throw new Error(`Server ${serverExit ?? "exited"}: ${serverLog}`);
  }
  try {
    process.kill(server.pid, 0);
  } catch (error) {
    throw new Error(`Spawned server is not alive: ${error.message}`);
  }
}

function probe(port) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host: "127.0.0.1", port });
    let received = Buffer.alloc(0);
    let settled = false;
    const finish = (ready) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(ready);
    };
    socket.setTimeout(500, () => finish(false));
    socket.once("error", () => finish(false));
    socket.once("connect", () => socket.write("list-tubes\r\n"));
    socket.on("data", (data) => {
      received = Buffer.concat([received, data]);
      if (received.includes(Buffer.from("\r\n"))) finish(received.toString("ascii").startsWith("OK "));
    });
    socket.once("close", () => finish(false));
  });
}

async function start(port) {
  let executable;
  let serverArgs;
  if (isWindows) {
    pidFile = path.join(cache, `server-${randomUUID()}.pid`);
    [executable, serverArgs] = serverCommand([
      "sh", "-c", 'echo $$ > "$1"; exec "$2" -l 127.0.0.1 -p "$3"',
      "with-beanstalkd", linuxPath(pidFile), linuxPath(binary), String(port),
    ]);
  } else {
    [executable, serverArgs] = serverCommand([binary, "-l", "127.0.0.1", "-p", String(port)]);
  }
  server = spawn(executable, serverArgs, { windowsHide: true, stdio: ["ignore", "pipe", "pipe"] });
  server.stdout.on("data", (data) => { serverLog += data; });
  server.stderr.on("data", (data) => { serverLog += data; });
  server.once("error", (error) => { serverExit = error.message; });
  server.once("exit", (code, signal) => { serverExit = `exit ${code}, signal ${signal}`; });
  const deadline = Date.now() + 15_000;
  while (Date.now() < deadline) {
    assertServerAlive();
    const ready = await probe(port);
    // Let pending child-exit events settle before accepting a peer's response.
    await delay(0);
    assertServerAlive();
    if (ready) return;
    await delay(100);
  }
  throw new Error(`Server readiness timed out: ${serverLog}`);
}

function stopChild() {
  if (!child || child.exitCode !== null || child.signalCode !== null) return;
  if (isWindows) {
    spawnSync("taskkill", ["/PID", String(child.pid), "/T", "/F"], { windowsHide: true, stdio: "ignore" });
  } else {
    try { process.kill(-child.pid, "SIGTERM"); } catch {}
  }
}

async function stop() {
  if (stopping) return;
  stopping = true;
  stopChild();
  if (isWindows && pidFile && existsSync(pidFile)) {
    const pid = readFileSync(pidFile, "utf8").trim();
    if (/^[1-9][0-9]*$/.test(pid)) {
      spawnSync("wsl.exe", ["-d", distro, "--exec", "kill", "-TERM", "--", pid], {
        timeout: 5_000, windowsHide: true, stdio: "ignore",
      });
    }
    rmSync(pidFile, { force: true });
  } else {
    server?.kill("SIGTERM");
  }
  if (server && server.exitCode === null && server.signalCode === null) {
    await Promise.race([new Promise((resolve) => server.once("exit", resolve)), delay(2_000)]);
    server.kill("SIGKILL");
  }
}

async function main() {
  if (options.some((option) => option !== "--prepare") || (!prepareOnly && command.length === 0)) {
    throw new Error("Usage: node scripts/with-beanstalkd.mjs --prepare | -- <command> [args]");
  }
  if (!Number.isSafeInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 600_000) {
    throw new Error("BEANSTALKD_TEST_TIMEOUT_MS must be 1..600000");
  }
  await prepare();
  if (prepareOnly) return;
  const port = await availablePort();
  await start(port);
  console.log(`beanstalkd listening on 127.0.0.1:${port}; command limit ${timeoutMs} ms`);
  process.exitCode = await new Promise((resolve, reject) => {
    child = spawn(command[0], command.slice(1), {
      cwd: root,
      stdio: "inherit",
      windowsHide: true,
      detached: !isWindows,
      env: { ...process.env, BEANSTALKD_HOST: "127.0.0.1", BEANSTALKD_PORT: String(port) },
    });
    const timer = setTimeout(() => {
      stopChild();
      reject(new Error(`Command exceeded ${timeoutMs} ms`));
    }, timeoutMs);
    child.once("error", (error) => { clearTimeout(timer); reject(error); });
    child.once("exit", (code, signal) => {
      clearTimeout(timer);
      signal ? reject(new Error(`Command stopped by ${signal}`)) : resolve(code ?? 1);
    });
  });
}

for (const signal of ["SIGINT", "SIGTERM"]) {
  process.once(signal, async () => {
    await stop();
    process.exit(signal === "SIGINT" ? 130 : 143);
  });
}

try {
  await main();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await stop();
}
