# rndrSBC — Deployment Repo

This is the **operator-side** companion to the `rndrsbc` PyPI core package.

The core (`pip install rndrsbc`) ships the engine: scheduler, web dashboard,
widget framework, display drivers. It never holds user data — everything
writable lives in a deployment home set via `RNDRSBC_HOME` (default: the
directory you run from in self-contained mode).

This repo provides what the **operator/viewer** of a frame needs on top of the
core: config scaffolding, the community widget catalog, and service wiring.

---
## Relationship to the core

                          ┌─────────────────────────────┐
                          │   rndrsbc (PyPI / pip)      │  ← engine: code only
                          │  core, displays, widgets,   │     read-only, upgraded
                          │  server, rndrsbc CLI        │     with `pip install -U`
                          └──────────────┬──────────────┘
                                         │  imports / runs
                          ┌──────────────▼──────────────┐
    THIS REPO ───────────►│  RNDRSBC_HOME (deploy home) │  ← state: config.json,
                          │  config.json, data/,        │     data/, plugins/,
                          │  plugins/, registry/        │     registry/. User-owned,
                          └─────────────────────────────┘     survives upgrades.

The two never mix: a wheel upgrade can't overwrite your config or community
widgets, because they live outside site-packages.

---
## What's in here

| Path | Purpose |
|------|---------|
| `examples/config.template.json` | Default config; copy to `config.json` |
| `catalog/sample_catalog.json`   | Example community widget feed (see schema) |
| `service/rndrsbc.service`       | Optional systemd unit for boot autostart |
| `bootstrap.sh`                  | One-shot: create deploy home + config.json |

---
## Quick start (two install modes)

### A. Self-contained (no pip, no internet beyond core)
```bash
cp -r rndrSBC /home/pi/ && cd /home/pi/rndrSBC
./bootstrap.sh --home /home/pi/rndrSBC   # scaffolds config.json
python3 main.py 8080
```

### B. PyPI install (recommended for ongoing upgrades)
```bash
pip install rndrsbc

# Create a deployment home & config on the Pi
export RNDRSBC_HOME=~/.rndrsbc
rndrsbc --home "$RNDRSBC_HOME" install-demo-config   # (see bootstrap.sh)
rndrsbc 8080

# Upgrade the engine only (data preserved)
pip install -U rndrsbc
```

### Community widgets — no git clone
```bash
rndrsbc search weather
rndrsbc install sonos_now_playing
rndrsbc list
```
Artifacts are downloaded, SHA-256 verified against the catalog feed, unpacked
into `$RNDRSBC_HOME/plugins/`, and auto-discovered on the next render cycle.

---
## Contributors: adding a widget to the community catalog

1. Package your widget as a zip (`widget.py` + assets).
2. Open a PR to the **registry** repo adding a catalog entry with a SHA-256 of
   your artifact (see `catalog/sample_catalog.json`).
3. Reviewers verify; merge publishes the feed. Users then get it via
   `rndrsbc search` / `rndrsbc install`.

Git is only ever on the maintainer side — end users never clone anything.
