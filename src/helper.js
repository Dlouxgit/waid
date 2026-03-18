import { spawn, spawnSync } from "node:child_process";
import { mkdir, stat } from "node:fs/promises";
import os from "node:os";
import path from "node:path";

async function fileMTimeMs(filePath) {
  try {
    const info = await stat(filePath);
    return info.mtimeMs;
  } catch (error) {
    if (error.code === "ENOENT") {
      return 0;
    }
    throw error;
  }
}

function shellEscape(value) {
  return `'${String(value).replace(/'/g, `'\\''`)}'`;
}

export async function ensureHelperBuilt(rootDir) {
  const runtimeDir = os.tmpdir();
  const cacheDir = path.join(runtimeDir, "waid-swift-cache");
  const sourcePath = path.join(rootDir, "native", "FrontmostTracker.swift");
  const binaryPath = path.join(runtimeDir, "waid-frontmost-tracker");

  await mkdir(cacheDir, { recursive: true });

  const [sourceMTime, binaryMTime] = await Promise.all([
    fileMTimeMs(sourcePath),
    fileMTimeMs(binaryPath),
  ]);

  if (binaryMTime >= sourceMTime && binaryMTime > 0) {
    return binaryPath;
  }

  console.log("Building macOS helper. The first launch can take around 20 seconds.");

  const environment = {
    ...process.env,
    TMPDIR: os.tmpdir(),
    SWIFT_MODULECACHE_PATH: cacheDir,
    CLANG_MODULE_CACHE_PATH: cacheDir,
  };

  const buildCommand = [
    "swiftc",
    "-framework",
    "AppKit",
    "-module-cache-path",
    cacheDir,
    "-o",
    binaryPath,
    sourcePath,
  ]
    .map(shellEscape)
    .join(" ");

  const result = spawnSync("/bin/zsh", ["-lc", buildCommand], {
    cwd: rootDir,
    encoding: "utf8",
    env: environment,
  });

  if (result.status !== 0) {
    const details = [result.stdout, result.stderr, result.error?.message]
      .filter(Boolean)
      .join("\n")
      .trim();
    throw new Error(`Failed to build Swift helper.\n${details}`);
  }

  return binaryPath;
}

export function spawnHelper(binaryPath) {
  return spawn(binaryPath, [], {
    stdio: ["ignore", "pipe", "ignore"],
  });
}
