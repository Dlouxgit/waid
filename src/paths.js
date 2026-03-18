import os from "node:os";
import path from "node:path";

export function appSupportDir(appName = "Waid") {
  if (process.platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", appName);
  }

  return path.join(process.cwd(), "data");
}

export function usageDataFilePath() {
  return path.join(appSupportDir(), "usage-data.json");
}
