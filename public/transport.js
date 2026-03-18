function appTransportAvailable() {
  return (
    typeof window !== "undefined" &&
    typeof window.WaidAppTransport?.subscribe === "function"
  );
}

function createUrl(pathname) {
  return new URL(pathname, window.location.href);
}

function connectWithPollingTransport({ onSnapshot, onStatus }) {
  let closed = false;

  const refresh = async () => {
    if (closed) {
      return;
    }

    try {
      const response = await fetch(createUrl("./api/dashboard"), {
        cache: "no-store",
      });
      const payload = await response.json();
      onSnapshot(payload);
      onStatus("live");
    } catch {
      onStatus("offline");
    }
  };

  onStatus("connecting");
  refresh();

  const pollTimer = window.setInterval(() => {
    refresh();
  }, 1000);

  return () => {
    closed = true;
    window.clearInterval(pollTimer);
  };
}

function connectWithWebTransport({ onSnapshot, onStatus }) {
  let closed = false;
  let source = null;

  const openStream = async () => {
    onStatus("connecting");

    try {
      const response = await fetch(createUrl("./api/dashboard"), {
        cache: "no-store",
      });

      if (response.ok) {
        onSnapshot(await response.json());
      }
    } catch {
      onStatus("offline");
    }

    if (closed) {
      return;
    }

    source = new EventSource(createUrl("./events"));

    source.onopen = () => {
      onStatus("live");
    };

    source.onmessage = (event) => {
      onSnapshot(JSON.parse(event.data));
    };

    source.onerror = () => {
      onStatus("offline");
    };
  };

  openStream();

  return () => {
    closed = true;
    source?.close();
  };
}

function connectWithAppTransport({ onSnapshot, onStatus }) {
  let lastSnapshotAt = 0;
  const unsubscribeSnapshot = window.WaidAppTransport.subscribe((snapshot) => {
    lastSnapshotAt = Date.now();
    onStatus("live");
    onSnapshot(snapshot);
  });

  const unsubscribeStatus =
    typeof window.WaidAppTransport.subscribeStatus === "function"
      ? window.WaidAppTransport.subscribeStatus(onStatus)
      : null;

  onStatus("connecting");
  window.WaidAppTransport.requestSnapshot?.();

  const pollTimer = window.setInterval(() => {
    window.WaidAppTransport.requestSnapshot?.();

    if (lastSnapshotAt === 0) {
      return;
    }

    if (Date.now() - lastSnapshotAt > 3000) {
      onStatus("connecting");
    }
  }, 1000);

  return () => {
    window.clearInterval(pollTimer);
    unsubscribeSnapshot?.();
    unsubscribeStatus?.();
  };
}

export function connectDashboard(handlers) {
  if (typeof window !== "undefined" && window.location.protocol === "waid:") {
    return connectWithPollingTransport(handlers);
  }

  if (appTransportAvailable()) {
    return connectWithAppTransport(handlers);
  }

  return connectWithWebTransport(handlers);
}
