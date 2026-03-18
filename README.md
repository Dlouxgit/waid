<p align="center">
  <img src="./public/favicon.png" alt="Waid logo" width="128" />
</p>

<h1 align="center">Waid</h1>

<p align="center">A local macOS time tracker for the app you are currently focused on.</p>

It answers a simple question: where did today actually go?

Waid watches only the frontmost app on your Mac, keeps the data on your machine, and shows a local dashboard with your current focus, daily totals, and a session timeline.

## Features

- Tracks the frontmost macOS app in real time
- Shows the app you are using right now
- Aggregates today's time by app
- Keeps a session timeline for the day
- Pauses tracking when the session is inactive or the screen sleeps
- Stores data locally in JSON
- Runs without full Xcode

## Quick start

Requirements:

- macOS
- `node`
- `swiftc` from Apple's Command Line Tools

```bash
git clone git@github.com:Dlouxgit/waid.git
cd waid
./run.sh
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

## Alternative start

```bash
node server.js
```

## How it works

- A tiny Swift helper listens for frontmost app changes through macOS `NSWorkspace`.
- A local Node server stores usage sessions in `data/usage-data.json`.
- A browser dashboard on `localhost` shows the current app, today's totals, and a timeline.

## Privacy

Waid is local-first.

- Data stays in this folder under `data/`.
- The app only listens for the frontmost app name and bundle identifier.
- It does not inspect what you do inside an app.
- It does not collect URLs, window titles, keystrokes, or screen content.

See [PRIVACY.md](./PRIVACY.md) for the exact data model and local-network behavior.

## Troubleshooting

- The first launch compiles the macOS helper and can take around 20 seconds.
- The tracker stops counting when the session becomes inactive or the screen sleeps.
- If the process exits unexpectedly, Waid recovers the last active session up to the most recent heartbeat it saved.
- If `swiftc` is missing, run `xcode-select --install`.
- If port `4312` is already in use, stop the existing Waid process before starting another one.

## Development

- Entry point: [server.js](./server.js)
- Swift tracker: [native/FrontmostTracker.swift](./native/FrontmostTracker.swift)
- Dashboard UI: [public/app.js](./public/app.js), [public/styles.css](./public/styles.css)
- Storage model: [src/store.js](./src/store.js)

See [CONTRIBUTING.md](./CONTRIBUTING.md) for basic contribution notes.

## Roadmap

- Export daily summaries
- Add a menu bar mode
- Add app categories and custom labels
- Add a packaged macOS release for non-technical users

## License

MIT. See [LICENSE](./LICENSE).
