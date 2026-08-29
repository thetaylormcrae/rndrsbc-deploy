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
VENV_DIR="${VENV_DIR:-${HOME:-$HOME}/.venvs/rndrsbc}"
DEPLOY_HOME="${RNDRSBC_HOME:-${HOME:-$HOME}/.rndrsbc}"
SERVICE_USER="${SERVICE_USER:-${USER:-$(id -un)}}"
INSTALL_SERVICE="${INSTALL_SERVICE:-no}"     # set to 'yes' to also install systemd service
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
    -h|--help) usage; exit 0;;
    *) die "unknown option: $1 (try --help)";;
  esac
done

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
  log "installing system packages (python3, venv, git)..."
  apt-get update -qq
  apt-get install -y -qq "$PY_BIN" "${PY_BIN}"-venv python3-pip git
fi

# ---- 2. virtualenv ---------------------------------------------------------
if [ ! -x "$VENV_DIR/bin/python" ]; then
  log "creating virtualenv at $VENV_DIR"
  "$PY_BIN" -m venv "$VENV_DIR"
else
  log "reusing virtualenv at $VENV_DIR"
fi

# ---- 3. engine from PyPI ---------------------------------------------------
log "installing/upgrading rndrsbc engine (PyPI, [pi] extra)..."
"$VENV_DIR/bin/pip" install -q --upgrade pip
"$VENV_DIR/bin/pip" install -q --upgrade "rndrsbc[pi]"

VERSION=$("$VENV_DIR/bin/rndrsbc" version 2>/dev/null || "$VENV_DIR/bin/python" -c 'import core; print(getattr(core,"__version__","?"))')
log "engine version: ${VERSION:-?}"
command -v "$VENV_DIR/bin/rndrsbc" >/dev/null 2>&1 || \
  die "engine installed but CLI not found; check 'pip show rndrsbc'"

# ---- 4. deploy home scaffold ----------------------------------------------
log "scaffolding deploy home at $DEPLOY_HOME"
"$REPO_DIR/bootstrap.sh" --home "$DEPLOY_HOME"

# ---- 5. systemd service ----------------------------------------------------
SERVICE_FILE="$REPO_DIR/service/rndrsbc.service"
BIN_PATH="$VENV_DIR/bin/rndrsbc"
if [ "$INSTALL_SERVICE" = "yes" ]; then
  if [ "$(id -u)" -ne 0 ]; then
    die "--with-service requires root (sudo). Add --no-deps if packages are already present."
  fi
  log "installing systemd unit for user '${SERVICE_USER}' (ExecStart=$BIN_PATH)"
  sed -e "s|^ExecStart=.*|ExecStart=${BIN_PATH} 8080|" \
      -e "s|^Environment=RNDRSBC_HOME=.*|Environment=RNDRSBC_HOME=${DEPLOY_HOME}|" \
      -e "s|^User=%i|User=${SERVICE_USER}|" \
      -e "s|^Group=%i|Group=${SERVICE_USER}|" \
      "$SERVICE_FILE" > /etc/systemd/system/rndrsbc-${SERVICE_USER}.service
  systemctl daemon-reload
  log "unit installed: rndrsbc-${SERVICE_USER}  (enable/start with systemctl)"
fi

# ---- done ------------------------------------------------------------------
log "install complete."
printf '\n'
printf '\033[1;32mrndrSBC install complete\033[0m\n'
printf '  engine : %s\n' "${VERSION:-?}"
printf '  venv   : %s\n' "$VENV_DIR"
printf '  home   : %s  (export RNDRSBC_HOME=%s)\n\n' "$DEPLOY_HOME" "$DEPLOY_HOME"
printf 'Run it now:\n  export RNDRSBC_HOME=%s\n  %s 8080\n' "$DEPLOY_HOME" "$BIN_PATH"
printf '\nWidget install & access docs: see README.md\n'
