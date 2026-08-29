# rndrSBC — Deployment Repo

![GitHub last commit](https://img.shields.io/github/last-commit/thetaylormcrae/rndrsbc-deploy)
![License](https://img.shields.io/github/license/thetaylormcrae/rndrsbc)
![Engine](https://img.shields.io/pypi/v/rndrsbc?label=rndrsbc%20engine)
[![rndrsbc engine](https://img.shields.io/github/v/release/thetaylormcrae/rndrsbc?label=core%20release)](https://github.com/thetaylormcrae/rndrsbc/releases)

This is the **operator-side** companion to the [`rndrsbc`](https://github.com/thetaylormcrae/rndrsbc) PyPI core package.

The core (`pip install rndrsbc`) ships the engine: scheduler, web dashboard,
widget framework, display drivers. It never holds user data — everything
writable lives in a deployment home set via `RNDRSBC_HOME` (default: the
directory you run from in self-contained mode).

This repo provides what the **operator/viewer** of a frame needs on top of the
core: config scaffolding, the community widget catalog, and service wiring.

> **Engine version tracking:** this repo's `catalog` pins `min_core: "0.3.0"`
> (the release that ships display auto-detection). The engine itself upgrades
> independently via `pip install -U rndrsbc` — this repo never holds wheel/code.

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
#   (use the scaffold from the repo: ./bootstrap.sh --home "$RNDRSBC_HOME")
export RNDRSBC_HOME=~/.rndrsbc
mkdir -p "$RNDRSBC_HOME"/{data,plugins,registry}
cp examples/config.template.json "$RNDRSBC_HOME"/config.json
rndrsbc 8080

# Upgrade the engine only (data preserved)
pip install -U rndrsbc
```

**Display auto-detection (v0.3.0+):** the default `driver: auto` probes for an
Inky panel at startup and renders to the virtual display only if no panel is
found (or when running headless). No manual `model` choice is required for
standard Pimoroni panels.

### Community widgets — no git clone
```bash
rndrsbc search weather
rndrsbc install sonos_now_playing
rndrsbc list
```
Artifacts are downloaded, SHA-256 verified against the catalog feed, unpacked
into `$RNDRSBC_HOME/plugins/`, and auto-discovered on the next render cycle.

### Fresh install on a Raspberry Pi (from scratch)

```bash
sudo apt update && sudo apt install -y python3-venv git

git clone https://github.com/thetaylormcrae/rndrsbc-deploy.git ~/rndrsbc
cd ~/rndrsbc

python3 -m venv ~/.venvs/rndrsbc && source ~/.venvs/rndrsbc/bin/activate
pip install -U pip
pip install rndrsbc          # 0.3.0
rndrsbc version              # expect: 0.3.0

# scaffold a deploy home + auto-detecting config:
export RNDRSBC_HOME="$HOME/.rndrsbc"
./bootstrap.sh --home "$RNDRSBC_HOME"

grep '"driver"' "$RNDRSBC_HOME/config.json"   # -> "auto"
rndrsbc 8080                 # boots the frame
```

Boot service (optional): copy `service/rndrsbc.service` to
`/etc/systemd/system/`, point `ExecStart` at your venv's `rndrsbc` binary and set
`Environment=RNDRSBC_HOME=...`, then `systemctl enable --now rndrsbc`.

---

## License

Operates under the same license as the core `rndrsbc` engine. Config scaffold,
catalog samples, and service wiring are original work.

---
## Contributors: adding a widget to the community catalog

1. Package your widget as a zip (`widget.py` + assets).
2. Open a PR to the **registry** repo adding a catalog entry with a SHA-256 of
   your artifact (see `catalog/sample_catalog.json`).
3. Reviewers verify; merge publishes the feed. Users then get it via
   `rndrsbc search` / `rndrsbc install`.

Git is only ever on the maintainer side — end users never clone anything.
