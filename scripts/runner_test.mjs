import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import net from "node:net";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));

function runRunner(code, env = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [
      "scripts/with-beanstalkd.mjs", "--", process.execPath, "-e", code,
    ], {
      cwd: root,
      env: { ...process.env, BEANSTALKD_PORT: "", ...env },
      windowsHide: true,
      timeout: 45_000,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (data) => { stdout += data; });
    child.stderr.on("data", (data) => { stderr += data; });
    child.once("error", reject);
    child.once("close", (exitCode, signal) => resolve({ exitCode, signal, stdout, stderr }));
  });
}

test("occupied requested port cannot substitute a mock for the pinned server", async (t) => {
  let connections = 0;
  const mock = net.createServer((socket) => {
    connections += 1;
    socket.on("error", () => {});
    socket.on("data", () => socket.write("OK 4\r\n---\n\r\n"));
  });
  await new Promise((resolve, reject) => {
    mock.once("error", reject);
    mock.listen(0, "127.0.0.1", resolve);
  });
  t.after(() => new Promise((resolve) => mock.close(resolve)));
  const port = mock.address().port;
  const result = await runRunner('console.log("CHILD_SHOULD_NOT_RUN")', {
    BEANSTALKD_PORT: String(port),
  });
  assert.equal(result.exitCode, 1, result.stdout + result.stderr);
  assert.equal(result.signal, null);
  assert.match(result.stderr, /already occupied \(EADDRINUSE\)/);
  assert.doesNotMatch(result.stdout, /CHILD_SHOULD_NOT_RUN/);
  assert.equal(connections, 0, "occupied-port check must not probe the unrelated listener");
  assert.equal(mock.listening, true, "runner must leave the unrelated listener alive");
});

test("a successful command receives its own server and the port closes afterward", async () => {
  const result = await runRunner(`
    const net = require("node:net");
    const port = Number(process.env.BEANSTALKD_PORT);
    const socket = net.connect({ host: process.env.BEANSTALKD_HOST, port });
    socket.setTimeout(1000, () => { socket.destroy(); process.exitCode = 1; });
    socket.once("error", () => { process.exitCode = 1; });
    socket.once("connect", () => socket.write("list-tubes\\r\\n"));
    socket.once("data", (data) => {
      if (!data.toString("ascii").startsWith("OK ")) process.exitCode = 1;
      console.log("CHILD_PORT=" + port);
      socket.destroy();
    });
  `);
  assert.equal(result.exitCode, 0, result.stdout + result.stderr);
  const port = Number(result.stdout.match(/CHILD_PORT=(\d+)/)?.[1]);
  assert.ok(port, result.stdout);
  const error = await new Promise((resolve) => {
    const socket = net.connect({ host: "127.0.0.1", port });
    socket.once("connect", () => { socket.destroy(); resolve(null); });
    socket.once("error", resolve);
    socket.setTimeout(1000, () => { socket.destroy(); resolve(new Error("port check timed out")); });
  });
  assert.equal(error?.code, "ECONNREFUSED", "owned server port must close after command exit");
});
