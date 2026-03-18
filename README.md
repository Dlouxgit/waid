<p align="center">
  <img src="./public/favicon.png" alt="Waid logo" width="128" />
</p>

<h1 align="center">Waid</h1>

<p align="center">A local macOS time tracker for the app you are currently focused on.</p>

It answers a simple question: where did today actually go?

Waid watches only the frontmost app on your Mac, keeps the data on your machine, and shows a local dashboard with your current focus, daily totals, and a session timeline.

You can use Waid in two ways:

- `web`: run the local Node dashboard and open it in your browser
- `app`: build a standalone macOS `.app` that uses the same UI without Node

## Features

- Tracks the frontmost macOS app in real time
- Shows the app you are using right now
- Aggregates today's time by app
- Keeps a session timeline for the day
- Pauses tracking when the session is inactive or the screen sleeps
- Stores data locally in JSON
- Runs without full Xcode

## Quick start

### Web mode

Requirements:

- macOS
- `node`
- `swiftc` from Apple's Command Line Tools

```bash
git clone git@github.com:Dlouxgit/waid.git
cd waid
npm run dev:web
```

Then open:

```text
http://127.0.0.1:4312
```

There is no `npm install` step.

You do not need full Xcode to run this project.

If `swiftc` is missing, install Command Line Tools with:

```bash
xcode-select --install
```

`./run.sh` still works and starts the same web mode.

## App mode

Build a local macOS app bundle:

```bash
npm run build:app
```

This creates:

```text
dist/Waid.app
```

Or build and open it immediately:

```bash
npm run dev:app
```

The app mode:

- does not require Node at runtime
- does not use `localhost`
- loads the dashboard UI from the app bundle
- stores data in `~/Library/Application Support/Waid/usage-data.json`

## Alternative start

```bash
node server.js
```

## How it works

### Web mode

- A tiny Swift helper listens for frontmost app changes through macOS `NSWorkspace`.
- A local Node server stores usage sessions in `~/Library/Application Support/Waid/usage-data.json`.
- A browser dashboard on `localhost` shows the current app, today's totals, and a timeline.

### App mode

- A native macOS shell uses `WKWebView` to load the bundled dashboard UI.
- The app listens for frontmost app changes directly through `NSWorkspace`.
- The app pushes snapshot updates into the UI bridge without `SSE` or a local HTTP server.
- Data is stored in `~/Library/Application Support/Waid/usage-data.json`.

## Privacy

Waid is local-first.

- Data stays in this folder under `data/`.
- The app only listens for the frontmost app name and bundle identifier.
- It does not inspect what you do inside an app.
- It does not collect URLs, window titles, keystrokes, or screen content.

See [PRIVACY.md](./PRIVACY.md) for the exact data model and local-network behavior.

## Troubleshooting

- The first web launch compiles the Swift helper and can take around 20 seconds.
- The app build also requires `swiftc` from Apple's Command Line Tools.
- The tracker stops counting when the session becomes inactive or the screen sleeps.
- If the process exits unexpectedly, Waid recovers the last active session up to the most recent heartbeat it saved.
- If `swiftc` is missing, run `xcode-select --install`.
- If port `4312` is already in use, stop the existing Waid process before starting another one.

## Development

- Entry point: [server.js](./server.js)
- Swift tracker: [native/FrontmostTracker.swift](./native/FrontmostTracker.swift)
- App shell: [app/Sources/AppDelegate.swift](./app/Sources/AppDelegate.swift), [app/Sources/WebBridgeController.swift](./app/Sources/WebBridgeController.swift)
- Dashboard UI: [public/app.js](./public/app.js), [public/styles.css](./public/styles.css)
- Web storage model: [src/store.js](./src/store.js)
- Shared web/app transport boundary: [public/transport.js](./public/transport.js)

See [CONTRIBUTING.md](./CONTRIBUTING.md) for basic contribution notes.

## Roadmap

- Export daily summaries
- Add a menu bar mode
- Add app categories and custom labels
- Add a packaged macOS release for non-technical users

## License

MIT. See [LICENSE](./LICENSE).
