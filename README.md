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
> Current engine on PyPI: **0.7.1**.

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

**Display config (hardware-first):** the default `config.template.json` uses
`driver: "auto"` with `model: "spectra6"` (Inky Impression 7.3" Spectra 6,
800×480, 7-colour). `driver: auto` probes the attached Inky panel at startup
and renders to the virtual display only if no panel is found (or when running
headless) — so the `model` field is a default, not a hard requirement.

### Community widgets — no git clone
```bash
rndrsbc search weather
rndrsbc install sonos_now_playing
rndrsbc list
```
Artifacts are downloaded, SHA-256 verified against the catalog feed, unpacked
into `$RNDRSBC_HOME/plugins/`, and auto-discovered on the next render cycle.

### Fresh install on a Raspberry Pi (from scratch)

This repo is installable in one command via [`install.sh`](install.sh) —
engine + deploy home + optional boot service, all wired up:

```bash
sudo ./install.sh --with-service
```

That single command:

1. installs system packages (`python3`, `python3-venv`, `git`)
2. creates a virtualenv at `~/.venvs/rndrsbc` with `--system-site-packages`
   so apt-installed SPI/GPIO libs stay visible (no on-device C compilation)
3. `pip`-installs the **`rndrsbc[pi]`** engine from **pypi.org only** — the
   `--index-url` pin (no extra-index) drops piwheels' armv7l shadow so a newer
   rndrsbc wheel can never be masked by a stale Raspberry build
4. scaffolds a deploy home at `~/.rndrsbc` with a default `config.json`
   (`driver: "auto"`, `model: "spectra6"`) and `data/` `plugins/` `registry/`
5. registers the `systemd` boot service (from `--with-service`)

Manage afterwards:

```bash
export RNDRSBC_HOME="$HOME/.rndrsbc"
~/.venvs/rndrsbc/bin/rndrsbc 8080             # run in foreground
sudo systemctl enable --now rndrsbc-$USER     # or boot at startup
rndrsbc version                               # confirm engine version (0.7.1)
```

Flags: `--venv DIR`, `--home DIR`, `--with-service`, `--service-user U`,
`--no-deps` / `--deps`, `--python BIN` (+ `install.sh --help`).

> **Why an installer?** Code (the engine) ships on PyPI and upgrades
> independently; this repo carries state (config, catalog, service unit). The
> installer wires the two so an operator gets a working frame from this repo
> alone — that's exactly the point of splitting the deploy side into its own
> repo.

### Manually (same steps, done by hand)

```bash
sudo apt update && sudo apt install -y python3-venv git
sudo apt install -y python3-spidev python3-rpi.gpio python3-gpiod python3-smbus

git clone https://github.com/thetaylormcrae/rndrsbc-deploy.git ~/rndrsbc
cd ~/rndrsbc

python3 -m venv --system-site-packages ~/.venvs/rndrsbc && source ~/.venvs/rndrsbc/bin/activate
pip install -U pip
PIP_CONFIG_FILE=/dev/null pip install --index-url https://pypi.org/simple rndrsbc[pi]   # 0.7.1
rndrsbc version                # expect: 0.7.1

./bootstrap.sh --home "$RNDRSBC_HOME"       # scaffold deploy home + driver:auto config
rndrsbc 8080                   # boots the frame
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
