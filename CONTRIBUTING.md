# Contributing

## Development

```bash
git clone git@github.com:Dlouxgit/waid.git
cd waid
./run.sh
```

Waid has no `npm install` step right now.

## Project layout

- `native/`: macOS Swift helper for frontmost-app tracking
- `src/`: Node server, storage, and helper bootstrapping
- `public/`: dashboard UI

## Before opening a PR

- Keep the app local-first
- Do not commit `data/` or runtime artifacts
- Run:

```bash
bash -n run.sh
node --check server.js
node --check public/app.js
node --check src/helper.js
node --check src/store.js
node --check src/tracker.js
```
