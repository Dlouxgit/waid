import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import path from "node:path";

function emptyState() {
  return {
    version: 1,
    completedSessions: [],
    activeSession: null,
  };
}

function toIsoString(value) {
  return value instanceof Date ? value.toISOString() : new Date(value).toISOString();
}

function sameApp(left, right) {
  return (
    (left.bundleIdentifier && right.bundleIdentifier && left.bundleIdentifier === right.bundleIdentifier) ||
    left.appName === right.appName
  );
}

function localDateKey(value) {
  const date = value instanceof Date ? value : new Date(value);
  const year = String(date.getFullYear());
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function startOfLocalDay(value) {
  const date = value instanceof Date ? new Date(value) : new Date(value);
  date.setHours(0, 0, 0, 0);
  return date;
}

function startOfNextLocalDay(value) {
  const date = startOfLocalDay(value);
  date.setDate(date.getDate() + 1);
  return date;
}

function overlapMs(sessionStart, sessionEnd, rangeStart, rangeEnd) {
  const start = Math.max(sessionStart.getTime(), rangeStart.getTime());
  const end = Math.min(sessionEnd.getTime(), rangeEnd.getTime());
  return Math.max(0, end - start);
}

export class UsageStore {
  constructor(dataFilePath) {
    this.dataFilePath = dataFilePath;
    this.data = emptyState();
    this.saveQueue = Promise.resolve();
  }

  async load() {
    await mkdir(path.dirname(this.dataFilePath), { recursive: true });

    try {
      const fileContents = await readFile(this.dataFilePath, "utf8");
      this.data = JSON.parse(fileContents);
    } catch (error) {
      if (error.code !== "ENOENT") {
        throw error;
      }

      this.data = emptyState();
      await this.persist();
    }
  }

  async recoverActiveSession() {
    const active = this.data.activeSession;
    if (!active) {
      return;
    }

    const startedAt = new Date(active.startedAt);
    const endedAt = new Date(active.lastSeenAt ?? active.startedAt);

    if (endedAt > startedAt) {
      this.data.completedSessions.push({
        appName: active.appName,
        bundleIdentifier: active.bundleIdentifier ?? null,
        startedAt: toIsoString(startedAt),
        endedAt: toIsoString(endedAt),
        durationMs: endedAt.getTime() - startedAt.getTime(),
        source: "recovered",
      });
    }

    this.data.activeSession = null;
    await this.persist();
  }

  getActiveSession() {
    return this.data.activeSession;
  }

  async beginActiveSession(app, startedAt) {
    this.data.activeSession = {
      appName: app.appName,
      bundleIdentifier: app.bundleIdentifier ?? null,
      startedAt: toIsoString(startedAt),
      lastSeenAt: toIsoString(startedAt),
    };

    await this.persist();
  }

  async touchActiveSession(at) {
    if (!this.data.activeSession) {
      return;
    }

    this.data.activeSession.lastSeenAt = toIsoString(at);
    await this.persist();
  }

  async finishActiveSession(endedAt, source = "switch") {
    const active = this.data.activeSession;
    if (!active) {
      return;
    }

    const startedAt = new Date(active.startedAt);
    const finishedAt = new Date(endedAt);

    if (finishedAt > startedAt) {
      this.data.completedSessions.push({
        appName: active.appName,
        bundleIdentifier: active.bundleIdentifier ?? null,
        startedAt: toIsoString(startedAt),
        endedAt: toIsoString(finishedAt),
        durationMs: finishedAt.getTime() - startedAt.getTime(),
        source,
      });
    }

    this.data.activeSession = null;
    await this.persist();
  }

  async persist() {
    this.saveQueue = this.saveQueue
      .catch(() => {})
      .then(async () => {
        const tempPath = `${this.dataFilePath}.tmp`;
        await writeFile(tempPath, `${JSON.stringify(this.data, null, 2)}\n`, "utf8");
        await rename(tempPath, this.dataFilePath);
      });

    return this.saveQueue;
  }

  buildSnapshot(now = new Date()) {
    const snapshotTime = now instanceof Date ? now : new Date(now);
    const dayStart = startOfLocalDay(snapshotTime);
    const dayEnd = startOfNextLocalDay(snapshotTime);
    const appTotals = new Map();
    const sessions = [];

    const addSegment = (session, active = false) => {
      const startedAt = new Date(session.startedAt);
      const endedAt = new Date(session.endedAt);
      const durationMs = overlapMs(startedAt, endedAt, dayStart, dayEnd);

      if (durationMs <= 0) {
        return;
      }

      const clippedStart = new Date(Math.max(startedAt.getTime(), dayStart.getTime()));
      const clippedEnd = new Date(Math.min(endedAt.getTime(), dayEnd.getTime()));
      const key = session.bundleIdentifier ?? session.appName;
      const previous = appTotals.get(key) ?? {
        appName: session.appName,
        bundleIdentifier: session.bundleIdentifier ?? null,
        totalMs: 0,
      };

      previous.totalMs += durationMs;
      appTotals.set(key, previous);

      sessions.push({
        appName: session.appName,
        bundleIdentifier: session.bundleIdentifier ?? null,
        startedAt: clippedStart.toISOString(),
        endedAt: clippedEnd.toISOString(),
        durationMs,
        isActive: active,
      });
    };

    for (const session of this.data.completedSessions) {
      addSegment(session, false);
    }

    if (this.data.activeSession) {
      addSegment(
        {
          appName: this.data.activeSession.appName,
          bundleIdentifier: this.data.activeSession.bundleIdentifier ?? null,
          startedAt: this.data.activeSession.startedAt,
          endedAt: toIsoString(snapshotTime),
        },
        true,
      );
    }

    sessions.sort((left, right) => new Date(right.startedAt) - new Date(left.startedAt));

    const totalTrackedMs = Array.from(appTotals.values()).reduce(
      (total, item) => total + item.totalMs,
      0,
    );

    const apps = Array.from(appTotals.values())
      .sort((left, right) => right.totalMs - left.totalMs)
      .map((entry) => ({
        ...entry,
        share: totalTrackedMs === 0 ? 0 : entry.totalMs / totalTrackedMs,
      }));

    const current = this.data.activeSession
      ? {
          appName: this.data.activeSession.appName,
          bundleIdentifier: this.data.activeSession.bundleIdentifier ?? null,
          startedAt: this.data.activeSession.startedAt,
          elapsedMs: Math.max(
            0,
            snapshotTime.getTime() - new Date(this.data.activeSession.startedAt).getTime(),
          ),
        }
      : null;

    return {
      generatedAt: snapshotTime.toISOString(),
      today: {
        date: localDateKey(snapshotTime),
        totalTrackedMs,
        apps,
        sessions,
      },
      current,
    };
  }

  hasSameActiveApp(app) {
    const active = this.data.activeSession;
    if (!active) {
      return false;
    }
    return sameApp(active, app);
  }
}
