#!/usr/bin/env bash
# rndrSBC — one-shot installer for the deployment repo.
#
# Orchestrates a complete Raspberry Pi frame setup from this repo alone:
#  1. system packages (venv/git)
#  2. a Python virtualenv
#  3. the rndrsbc engine from PyPI (with the optional [pi] extra)
#  4. a deployment home + default config (via bootstrap.sh)
#  5. (optional) a systemd boot service
#
# Code (engine) lives in a venv; state (config/data/plugins/registry) lives in
# the deploy home. This installer wires both — it is the intended entry point.
set -euo pipefail

# ---- defaults --------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# If run via sudo, respect the actual invoking user (SUDO_USER)
REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
if [ "$REAL_USER" = "root" ] && [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="$SUDO_USER"
fi
REAL_HOME="$(eval echo "~${REAL_USER}")"
if [ ! -d "$REAL_HOME" ]; then
  REAL_HOME="${HOME:-/root}"
fi

VENV_DIR="${VENV_DIR:-${REAL_HOME}/.venvs/rndrsbc}"
DEPLOY_HOME="${RNDRSBC_HOME:-${REAL_HOME}/.rndrsbc}"
SERVICE_USER="${SERVICE_USER:-$REAL_USER}"
INSTALL_SERVICE="${INSTALL_SERVICE:-no}"     # set to 'yes' to also install systemd service
DO_UNINSTALL="${DO_UNINSTALL:-no}"            # set to 'yes' to remove service+venv+home
DO_DEPS="${DO_DEPS:-auto}"                    # apt before/yes/no (auto => require venv3/git, install if missing & run as root/sudo)
PY_BIN="${PY_BIN:-python3}"

log()  { printf '\033[1;34m[rndrsbc]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[rndrsbc] error:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOT
rndrSBC installer — install the engine + scaffold a deploy home in one step.

usage: $0 [options]

options:
  --venv DIR        virtualenv to create/use   (default: $VENV_DIR)
  --home DIR        deployment home            (default: \$RNDRSBC_HOME or $HOME/.rndrsbc)
  --with-service    also install the systemd boot service
  --service-user U  user that owns the service (default: \$USER)
  --no-deps         skip apt system packages
  --deps            force apt system packages (run as root/sudo)
  --python BIN      python interpreter         (default: python3)
  -u, --uninstall   remove the service, virtualenv, and deployment home
  -h, --help        show this help
EOT
}

# ---- parse args ------------------------------------------------------------
while [ $# -gt 0 ]; do
  case "$1" in
    --venv) VENV_DIR="$2"; shift 2;;
    --home) DEPLOY_HOME="$2"; shift 2;;
    --with-service) INSTALL_SERVICE="yes"; shift;;
    --service-user) SERVICE_USER="$2"; INSTALL_SERVICE="yes"; shift 2;;
    --no-deps) DO_DEPS="no"; shift;;
    --deps) DO_DEPS="yes"; shift;;
    --python) PY_BIN="$2"; shift 2;;
    -u|--uninstall) DO_UNINSTALL="yes"; shift;;
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (try --help)";;
  esac
done

# ---- 0. uninstall ----------------------------------------------------------
if [ "${DO_UNINSTALL:-no}" = "yes" ]; then
  log "uninstall mode"
  [ "$(id -u)" -eq 0 ] || die "uninstall requires root (sudo)."

  # service
  if [ -f "/etc/systemd/system/rndrsbc-${SERVICE_USER}.service" ]; then
    systemctl disable --now "rndrsbc-${SERVICE_USER}.service" 2>/dev/null || true
    rm -f "/etc/systemd/system/rndrsbc-${SERVICE_USER}.service"
    systemctl daemon-reload
    log "removed systemd service rndrsbc-${SERVICE_USER}"
  else
    log "no systemd service for ${SERVICE_USER} to remove"
  fi

  # virtualenv
  if [ -d "$VENV_DIR" ]; then
    rm -rf "$VENV_DIR"
    log "removed virtualenv $VENV_DIR"
  else
    log "no virtualenv at $VENV_DIR to remove"
  fi

  # deploy home
  if [ -d "$DEPLOY_HOME" ]; then
    rm -rf "$DEPLOY_HOME"
    log "removed deploy home $DEPLOY_HOME"
  else
    log "no deploy home at $DEPLOY_HOME to remove"
  fi

  printf '\n\033[1;32mrndrSBC uninstall complete\033[0m\n'
  printf '  system packages were left in place (python/git); remove manually if desired.\n'
  exit 0
fi

# ---- 1. system packages ----------------------------------------------------
need_apt_deps() { command -v "${PY_BIN}" >/dev/null 2>&1 && command -v git >/dev/null 2>&1; }

if [ "$DO_DEPS" = "auto" ]; then
  if need_apt_deps; then
    DO_DEPS="no"
    log "python + git already present; skipping apt"
  else
    DO_DEPS="yes"
    log "python/git missing -> will install via apt"
  fi
fi

if [ "$DO_DEPS" = "yes" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    die "system packages require root. Re-run with sudo (add --no-deps to skip)."
  fi
  log "installing system packages (python3, venv, git, hostapd, dnsmasq)..."
  apt-get update -qq
  apt-get install -y -qq "$PY_BIN" "${PY_BIN}"-venv python3-pip git hostapd dnsmasq

  if command -v raspi-config >/dev/null 2>&1; then
    log "enabling Raspberry Pi SPI and I2C interfaces for e-paper displays..."
    raspi-config nonint do_spi 0 2>/dev/null || true
    raspi-config nonint do_i2c 0 2>/dev/null || true
  fi
fi

# ---- 1b. hardware libs + fonts (physical e-paper panel) -------------------
# The venv below is created with --system-site-packages so the prebuilt apt
# copies of the C drivers (spidev, RPi.GPIO, gpiod, smbus2) stay visible to the
# engine's Python. If these are missing, pip has to recompile rpi-gpio/spidev/
# gpiod/smbus2 from source on-device (slow, fragile on a Pi). Debconf may prompt
# on rpi-gpio; DEBIAN_FRONTEND noninteractive keeps it quiet.
HARDWARE_DEPS="python3-rpi.gpio python3-spidev python3-gpiod python3-smbus fonts-dejavu"
if [ "$DO_DEPS" != "no" ]; then
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    log "installing hardware libs + fonts (via sudo)..."
    sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $HARDWARE_DEPS \
      || log "WARNING: some apt hardware libs unavailable; the [pi] pip fallback will attempt a source build"
  elif [ "$(id -u)" -eq 0 ]; then
    log "installing hardware libs + fonts..."
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $HARDWARE_DEPS \
      || log "WARNING: some apt hardware libs unavailable; the [pi] pip fallback will attempt a source build"
  else
    log "WARNING: no root/sudo to apt-install hardware libs; the [pi] pip fallback will attempt a source build"
  fi
fi

# ---- 2. virtualenv ---------------------------------------------------------
if [ ! -x "$VENV_DIR/bin/python" ]; then
  log "creating virtualenv at $VENV_DIR"
  # --system-site-packages: hardware libs (spidev, RPi.GPIO, gpiod, smbus2)
  # are installed prebuilt via apt and must remain visible to the venv's
  # Python; otherwise pip recompiles their C extensions on-device.
  "$PY_BIN" -m venv --system-site-packages "$VENV_DIR"
else
  log "reusing virtualenv at $VENV_DIR"
fi

# ---- 3. engine from PyPI ---------------------------------------------------
log "installing/upgrading rndrsbc engine (PyPI, [pi] extra)..."
# Pin rndrsbc to pypi.org ONLY: the Pi's pip already fans in piwheels, which
# can shadow a newer rndrsbc wheel with an older armv7l build (the "stale",
# crashy 0.6.6 was served that way). PIP_CONFIG_FILE=/dev/null neutralises any
# ambient /etc/pip.conf; --index-url (no extra-index) drops piwheels for
# rndrsbc itself. Hardware libs still resolve fine below via apt/system-site.
PIP_CONFIG_FILE=/dev/null "$VENV_DIR/bin/pip" install -q --no-cache-dir --upgrade pip
PIP_CONFIG_FILE=/dev/null "$VENV_DIR/bin/pip" install -q --no-cache-dir --upgrade \
    --index-url https://pypi.org/simple \
    "rndrsbc[pi]"

VERSION=$("$VENV_DIR/bin/rndrsbc" version 2>/dev/null || "$VENV_DIR/bin/python" -c 'import core; print(getattr(core,"__version__","?"))')
log "engine version: ${VERSION:-?}"
command -v "$VENV_DIR/bin/rndrsbc" >/dev/null 2>&1 || \
  die "engine installed but CLI not found; check 'pip show rndrsbc'"

# Optional shell-level alias so `rndrsbc` works from an interactive shell, not
# just as the systemd unit. The service uses the venv's absolute path and is
# unaffected; this only adds a convenience symlink (root-owned, so the
# service-user ownership of DEPLOY_HOME/venv is left untouched). Skip when we
# can't write /usr/local/bin or when the engine ships no top-level script.
if [ "$(id -u)" -eq 0 ] && [ -w /usr/local/bin ] && [ -x "$VENV_DIR/bin/rndrsbc" ]; then
  if [ "$(readlink /usr/local/bin/rndrsbc 2>/dev/null)" != "$VENV_DIR/bin/rndrsbc" ]; then
    ln -sf "$VENV_DIR/bin/rndrsbc" /usr/local/bin/rndrsbc
    log "linked /usr/local/bin/rndrsbc -> $VENV_DIR/bin/rndrsbc (shell 'rndrsbc' now works)"
  fi
else
  log "SKIP: no root or /usr/local/bin unwritable — shell 'rndrsbc' not linked; use $VENV_DIR/bin/rndrsbc"
fi

# Persist pip hardening so future invocations "just work". The venv install
# above is hardened once (PIP_CONFIG_FILE=/dev/null + --no-cache-dir), but a
# later manual `sudo pip install --upgrade rndrsbc` runs as ROOT and reads
# root's config + HTTP cache — which can serve a stale index (the two 'still on
# 0.7.2' failures). Write a persistent root pip.conf: pypi.org-only (no piwheels
# shadowing of a newer wheel) + no-cache. Idempotent; only when running as root.
if [ "$(id -u)" -eq 0 ] && [ -d /root ]; then
  mkdir -p /root/.config/pip
  if ! grep -q "index-url = https://pypi.org/simple" /root/.config/pip/pip.conf 2>/dev/null; then
    cat > /root/.config/pip/pip.conf <<'PIPCONF'
[global]
index-url = https://pypi.org/simple
disable-pip-version-check = true
no-cache-dir = true
PIPCONF
    log "wrote /root/.config/pip/pip.conf (pypi.org-only, no-cache) so future 'sudo pip' resolves the latest rndrsbc"
  else
    log "root pip.conf already hardened (pypi.org-only, no-cache)"
  fi
else
  log "WARNING: not root — did not persist pip hardening; future 'sudo pip install' may hit stale root cache"
fi

# ---- 4. deploy home scaffold ----------------------------------------------
log "scaffolding deploy home at $DEPLOY_HOME"
"$REPO_DIR/bootstrap.sh" --home "$DEPLOY_HOME"

# The scaffold (and any pre-existing files) may be root-owned if install ran under
# sudo. The engine runs as the real user and must be able to write config/state
# (migrations, panel health, settings). Normalize ownership so writes never fail.
if [ "$REAL_USER" != "root" ]; then
  chown -R "${REAL_USER}":"${REAL_USER}" "$DEPLOY_HOME" 2>/dev/null \
    || log "WARNING: could not chown $DEPLOY_HOME to $REAL_USER"
fi

# Validate the existing config actually loads under THIS engine version.
# A stale/old-schema config (e.g. a pre-migration format) will crash the
# engine at startup; on install we prefer the current template over a
# broken file, so back it up and regenerate rather than leave a landmine.
if [ -f "$DEPLOY_HOME/config.json" ]; then
  VALID=1
  # NOTE: quoted heredoc would keep $DEPLOY_HOME literal and ALWAYS fail;
  # export + unquoted heredoc so the real path reaches Python.
  export RNDRSBC_CFG_PATH="$DEPLOY_HOME/config.json"
  "$VENV_DIR/bin/python" - <<PYEOF 2>/dev/null || VALID=0
import json, os
# the engine exposes its migration package as the top-level 'core'
mod = None
for name in ("core.migrations", "rndrsbc.core.migrations"):
    try:
        mod = __import__(name, fromlist=["migrate"])
        break
    except Exception:
        continue
if mod is None:
    sys.exit(0)  # can't import migrations -> leave config alone
cfg_path = os.environ["RNDRSBC_CFG_PATH"]
try:
    with open(cfg_path, "r") as fh:
        raw = json.load(fh)
except Exception:
    sys.exit(1)  # malformed / unparseable -> genuinely incompatible
if not isinstance(raw, dict):
    sys.exit(1)
try:
    mod.migrate(raw)
except Exception:
    sys.exit(1)  # migration crashes on this config -> incompatible
PYEOF
  if [ "$VALID" != "1" ]; then
    mv "$DEPLOY_HOME/config.json" "$DEPLOY_HOME/config.json.incompatible"
    "$REPO_DIR/bootstrap.sh" --home "$DEPLOY_HOME"   # regenerates fresh config.json
    log "existing config.json was incompatible with engine ${VERSION:-?}; backed it up as config.json.incompatible and regenerated from template"
  fi
fi

# ---- 5. systemd service ----------------------------------------------------
SERVICE_FILE="$REPO_DIR/service/rndrsbc.service"
BIN_PATH="$VENV_DIR/bin/rndrsbc"
if [ "$INSTALL_SERVICE" = "yes" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    die "--with-service requires root (sudo). Add --no-deps if packages are already present."
  fi
  log "installing systemd unit for user '${SERVICE_USER}' (ExecStart=$BIN_PATH)"
  # Hand the deploy home + virtualenv to the service user so the engine can
  # write config/state (migrations, panel health, settings). If any file was
  # created by a previous sudo/root run it stays root-owned and every write
  # fails with Permission denied — normalize ownership before starting.
  if [ "$SERVICE_USER" != "root" ]; then
    chown -R "${SERVICE_USER}":"${SERVICE_USER}" "$DEPLOY_HOME" "$VENV_DIR" 2>/dev/null \
      || log "WARNING: could not chown $DEPLOY_HOME/$VENV_DIR to $SERVICE_USER (run as root?)"
  fi
  sed -e "s|^ExecStart=.*|ExecStart=${BIN_PATH} 8080|" \
      -e "s|^Environment=RNDRSBC_HOME=.*|Environment=RNDRSBC_HOME=${DEPLOY_HOME}|" \
      -e "s|^User=%i|User=${SERVICE_USER}|" \
      -e "s|^Group=%i|Group=${SERVICE_USER}|" \
      "$SERVICE_FILE" > /etc/systemd/system/rndrsbc-${SERVICE_USER}.service
  systemctl daemon-reload

  # restart (even if already running) so the just-upgraded venv is actually loaded
  log "enabling + (re)starting rndrsbc-${SERVICE_USER}"
  systemctl enable rndrsbc-${SERVICE_USER}.service
  systemctl restart rndrsbc-${SERVICE_USER}.service
  sleep 2
  if systemctl is-active --quiet rndrsbc-${SERVICE_USER}.service; then
    SERVICE_STATE="running"
    log "service rndrsbc-${SERVICE_USER} is RUNNING"
  else
    SERVICE_STATE="FAILED"
    log "WARNING: rndrsbc-${SERVICE_USER} not active — logs below; run:'systemctl status rndrsbc-${SERVICE_USER}'"
    journalctl -u rndrsbc-${SERVICE_USER}.service -n 30 --no-pager 2>/dev/null | tail -30 || true
  fi
fi

# ---- done ------------------------------------------------------------------
PORT=8080
log "install complete."
printf '\n\033[1;32mrndrSBC install complete\033[0m\n'
printf '  engine : %s\n' "${VERSION:-?}"
printf '  venv   : %s\n' "$VENV_DIR"
printf '  home   : %s\n\n' "$DEPLOY_HOME"
if [ "$INSTALL_SERVICE" = "yes" ]; then
  printf '  service: rndrsbc-%s (enabled, %s)\n' "$SERVICE_USER" "${SERVICE_STATE:-?}"
  printf '  status : systemctl status rndrsbc-%s\n' "$SERVICE_USER"
  printf '  logs   : journalctl -u rndrsbc-%s -f\n' "$SERVICE_USER"
  printf '  bind   : ss -tlnp | grep %s\n' "$PORT"
  printf '  stop   : systemctl stop rndrsbc-%s\n' "$SERVICE_USER"
else
  printf '  run    : export RNDRSBC_HOME=%s\n           %s %s\n' "$DEPLOY_HOME" "$BIN_PATH" "$PORT"
fi
printf '\nWidget install & access docs: see README.md\n'
