# Privacy

Waid is designed to stay local.

## What Waid collects

- The frontmost app name
- The frontmost app bundle identifier
- Start and end timestamps for tracked sessions
- Aggregated daily usage durations derived from those sessions

## What Waid does not collect

- Window titles
- URLs
- File names
- Keystrokes
- Screen contents
- Clipboard contents
- Network activity

## Where data is stored

Waid stores usage data locally in:

```text
data/usage-data.json
```

This file is ignored by Git through `.gitignore` and is not meant to be committed.

## Network behavior

Waid serves a dashboard on:

```text
http://127.0.0.1:4312
```

It binds to `127.0.0.1`, which means it is only reachable from the same Mac.

## Things to keep in mind

- Usage data is stored in plain JSON on your machine.
- If you sync this project folder with a cloud drive, the data file may also be synced.
- Any other local process on the same machine that can access `127.0.0.1:4312` can read the dashboard data while Waid is running.
