import { connectDashboard } from "./transport.js";

const rootElement = document.documentElement;
const connectionPill = document.querySelector("#connection-pill");
const currentApp = document.querySelector("#current-app");
const currentMeta = document.querySelector("#current-meta");
const currentElapsed = document.querySelector("#current-elapsed");
const todayTotal = document.querySelector("#today-total");
const todayDate = document.querySelector("#today-date");
const appList = document.querySelector("#app-list");
const sessionList = document.querySelector("#session-list");

let latestSnapshot = null;

function setFocusMode(enabled) {
  rootElement.dataset.focusMode = enabled ? "true" : "false";
}

window.WaidDashboard = {
  ...(window.WaidDashboard ?? {}),
  setFocusMode,
};

setFocusMode(rootElement.dataset.focusMode === "true");

function appKey(entry) {
  return entry.bundleIdentifier ?? entry.appName ?? "unknown-app";
}

function sessionKey(session) {
  return `${appKey(session)}:${session.startedAt}`;
}

function formatDuration(totalMs, withSeconds = false) {
  const totalSeconds = Math.max(0, Math.floor(totalMs / 1000));

  if (totalSeconds === 0) {
    return withSeconds ? "0s" : "0m";
  }

  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (withSeconds) {
    if (hours > 0) {
      return `${hours}h ${minutes}m ${seconds}s`;
    }
    if (minutes > 0) {
      return `${minutes}m ${seconds}s`;
    }
    return `${seconds}s`;
  }

  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m`;
  }
  return `${seconds}s`;
}

function formatClock(value) {
  return new Intl.DateTimeFormat(undefined, {
    hour: "numeric",
    minute: "2-digit",
  }).format(new Date(value));
}

function getLiveDeltaMs(snapshot) {
  if (!snapshot?.current) {
    return 0;
  }

  const generatedAtMs = new Date(snapshot.generatedAt).getTime();
  return Math.max(0, Date.now() - generatedAtMs);
}

function buildLiveApps(snapshot) {
  const deltaMs = getLiveDeltaMs(snapshot);
  const activeKey = snapshot.current ? appKey(snapshot.current) : null;

  return snapshot.today.apps.map((app) => ({
    ...app,
    liveTotalMs: app.totalMs + (appKey(app) === activeKey ? deltaMs : 0),
  }));
}

function buildLiveTotalMs(snapshot) {
  return snapshot.today.totalTrackedMs + getLiveDeltaMs(snapshot);
}

function renderCurrent(snapshot) {
  if (!snapshot.current) {
    currentApp.textContent = "No active app detected";
    currentMeta.textContent = "Unlock your Mac or switch into an app to start tracking.";
    currentElapsed.textContent = "0m";
    return;
  }

  currentApp.textContent = snapshot.current.appName ?? snapshot.current.bundleIdentifier ?? "Unknown app";
  currentMeta.textContent = `Since ${formatClock(snapshot.current.startedAt)}`;
  currentElapsed.textContent = formatDuration(snapshot.current.elapsedMs, true);
}

function renderApps(snapshot) {
  if (snapshot.today.apps.length === 0) {
    appList.innerHTML = `
      <div class="empty-state">
        <p>No tracked app time yet.</p>
      </div>
    `;
    return;
  }

  const liveApps = buildLiveApps(snapshot);
  const totalMs = buildLiveTotalMs(snapshot) || 1;

  appList.innerHTML = liveApps
    .map((app, index) => {
      const width = Math.max(4, Math.round((app.liveTotalMs / totalMs) * 100));
      return `
        <article class="app-row" data-app-key="${appKey(app)}" style="--bar-width:${width}%">
          <div class="app-rank">#${index + 1}</div>
          <div class="app-main">
            <div class="app-copy">
              <h4>${app.appName ?? app.bundleIdentifier ?? "Unknown app"}</h4>
              <p class="app-duration">${formatDuration(app.liveTotalMs)}</p>
            </div>
            <div class="bar-track">
              <div class="bar-fill"></div>
            </div>
          </div>
        </article>
      `;
    })
    .join("");
}

function renderSessions(snapshot) {
  if (snapshot.today.sessions.length === 0) {
    sessionList.innerHTML = `
      <div class="empty-state">
        <p>Your timeline will appear after the first app switch.</p>
      </div>
    `;
    return;
  }

  sessionList.innerHTML = snapshot.today.sessions
    .map((session) => {
      const name = session.appName ?? session.bundleIdentifier ?? "Unknown app";
      const state = session.isActive ? "Live" : "Done";
      const range = session.isActive
        ? `${formatClock(session.startedAt)} to now`
        : `${formatClock(session.startedAt)} to ${formatClock(session.endedAt)}`;

      return `
        <article class="session-row ${session.isActive ? "session-row-live" : ""}" data-session-key="${sessionKey(session)}">
          <div>
            <div class="session-topline">
              <h4>${name}</h4>
              <span class="session-state">${state}</span>
            </div>
            <p>${range}</p>
          </div>
          <strong class="session-duration">${formatDuration(session.durationMs)}</strong>
        </article>
      `;
    })
    .join("");
}

function updateLiveMetrics(snapshot) {
  if (!snapshot) {
    return;
  }

  const deltaMs = getLiveDeltaMs(snapshot);
  const liveTotalMs = buildLiveTotalMs(snapshot);
  const liveApps = buildLiveApps(snapshot);
  const totalMs = liveTotalMs || 1;

  todayTotal.textContent = `${formatDuration(liveTotalMs)} tracked`;

  if (snapshot.current) {
    currentElapsed.textContent = formatDuration(snapshot.current.elapsedMs + deltaMs, true);
  }

  for (const app of liveApps) {
    const key = CSS.escape(appKey(app));
    const row = appList.querySelector(`[data-app-key="${key}"]`);

    if (!row) {
      continue;
    }

    const duration = row.querySelector(".app-duration");
    const width = Math.max(4, Math.round((app.liveTotalMs / totalMs) * 100));

    if (duration) {
      duration.textContent = formatDuration(app.liveTotalMs);
    }

    row.style.setProperty("--bar-width", `${width}%`);
  }

  if (snapshot.current) {
    const activeSession = snapshot.today.sessions.find((session) => session.isActive);

    if (activeSession) {
      const key = CSS.escape(sessionKey(activeSession));
      const row = sessionList.querySelector(`[data-session-key="${key}"]`);
      const duration = row?.querySelector(".session-duration");

      if (duration) {
        duration.textContent = formatDuration(activeSession.durationMs + deltaMs);
      }
    }
  }
}

function render(snapshot) {
  latestSnapshot = snapshot;
  connectionPill.textContent = "Live";
  connectionPill.dataset.state = "live";
  todayDate.textContent = snapshot.today.date;
  renderCurrent(snapshot);
  renderApps(snapshot);
  renderSessions(snapshot);
  updateLiveMetrics(snapshot);
}

function setDisconnected() {
  connectionPill.textContent = "Reconnecting";
  connectionPill.dataset.state = "offline";
}

connectDashboard({
  onSnapshot(snapshot) {
    render(snapshot);
  },
  onStatus(status) {
    if (status === "live") {
      connectionPill.textContent = "Live";
      connectionPill.dataset.state = "live";
      return;
    }

    setDisconnected();
  },
});

setInterval(() => {
  updateLiveMetrics(latestSnapshot);
}, 1000);
