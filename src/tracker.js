import { EventEmitter } from "node:events";
import readline from "node:readline";

import { ensureHelperBuilt, spawnHelper } from "./helper.js";

function normalizeApp(event) {
  return {
    appName: event.appName ?? null,
    bundleIdentifier: event.bundleIdentifier ?? null,
  };
}

export class TrackerService extends EventEmitter {
  constructor({ rootDir, store, log = console }) {
    super();
    this.rootDir = rootDir;
    this.store = store;
    this.log = log;
    this.childProcess = null;
    this.stopping = false;
    this.eventQueue = Promise.resolve();
    this.heartbeatTimer = null;
  }

  async start() {
    await this.store.load();
    await this.store.recoverActiveSession();
    await this.launchHelper();

    this.heartbeatTimer = setInterval(() => {
      this.enqueue(async () => {
        await this.store.touchActiveSession(new Date());
        this.emit("update", this.store.buildSnapshot());
      });
    }, 15000);
  }

  async stop() {
    this.stopping = true;

    if (this.heartbeatTimer) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }

    await this.enqueue(() => this.store.finishActiveSession(new Date(), "shutdown"));

    if (this.childProcess) {
      this.childProcess.kill("SIGTERM");
      this.childProcess = null;
    }
  }

  snapshot() {
    return this.store.buildSnapshot();
  }

  async launchHelper() {
    const helperPath = await ensureHelperBuilt(this.rootDir);
    const child = spawnHelper(helperPath);
    this.childProcess = child;

    const lines = readline.createInterface({ input: child.stdout });

    lines.on("line", (line) => {
      this.enqueue(() => this.processHelperLine(line));
    });

    child.on("close", (code) => {
      this.childProcess = null;
      if (this.stopping) {
        return;
      }

      this.log.warn(`Swift helper exited with code ${code ?? "unknown"}, restarting in 2s.`);
      this.enqueue(() => this.store.finishActiveSession(new Date(), "helper-exit")).then(() => {
        this.emit("update", this.store.buildSnapshot());
      });

      setTimeout(() => {
        if (!this.stopping) {
          this.launchHelper().catch((error) => {
            this.log.error(error);
          });
        }
      }, 2000);
    });
  }

  enqueue(task) {
    this.eventQueue = this.eventQueue
      .then(() => task())
      .catch((error) => {
        this.log.error(error);
      });

    return this.eventQueue;
  }

  async processHelperLine(line) {
    if (!line.trim()) {
      return;
    }

    let event;

    try {
      event = JSON.parse(line);
    } catch (error) {
      this.log.warn(`Failed to parse helper line: ${line}`);
      return;
    }

    const at = new Date(event.at ?? Date.now());

    if (Number.isNaN(at.getTime())) {
      return;
    }

    switch (event.type) {
      case "current":
      case "activate":
        await this.handleActivation(normalizeApp(event), at);
        break;
      case "pause":
      case "shutdown":
        await this.store.finishActiveSession(at, event.type);
        break;
      case "resume":
        break;
      default:
        this.log.warn(`Unknown helper event: ${event.type}`);
    }

    this.emit("update", this.store.buildSnapshot());
  }

  async handleActivation(app, at) {
    if (!app.appName && !app.bundleIdentifier) {
      await this.store.finishActiveSession(at, "missing-app");
      return;
    }

    if (this.store.hasSameActiveApp(app)) {
      await this.store.touchActiveSession(at);
      return;
    }

    await this.store.finishActiveSession(at, "switch");
    await this.store.beginActiveSession(app, at);
  }
}
