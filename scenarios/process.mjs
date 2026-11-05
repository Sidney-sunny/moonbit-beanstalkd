import { spawn } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const root = fileURLToPath(new URL("../", import.meta.url));

export function binary(example) {
  return path.join(root, "_build", "js", "debug", "build", "examples", example, `${example}.js`);
}

export function run(executable, args, { env = process.env, timeoutMs = 20_000 } = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(executable, args, {
      cwd: root, env, windowsHide: true, timeout: timeoutMs,
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

export async function build(example) {
  await run("moon", ["build", "--target", "js", `examples/${example}`], { timeoutMs: 120_000 });
}
