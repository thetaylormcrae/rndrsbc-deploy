#!/usr/bin/env bash
# rndrSBC — foolproof in-place reset. No OS reflash.
# Stops/conflicts ALL rndrsbc unit variants, wipes code + state, reinstalls
# from PyPI via install.sh. Config is preserved to config.json.reset-backup
# unless --wipe is given.
set -euo pipefail

REAL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
REAL_HOME="$(eval echo "~${REAL_USER}")"
VENV_DIR="${VENV_DIR:-$REAL_HOME/.venvs/rndrsbc}"
DEPLOY_HOME="${RNDRSBC_HOME:-$REAL_HOME/.rndrsbc}"
WIPE="no"
[ "${1:-}" = "--wipe" ] && WIPE="yes"

log()  { printf '\033[1;34m[rndrsbc-reset]\033[0m %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo ./reset.sh"; exit 1; }

log "stopping every rndrsbc unit variant (templated + flat + bare)..."
# 'disable --now' on patterns that may not exist; never fail on missing units.
for u in 'rndrsbc@*' "rndrsbc-${REAL_USER}.service" rndrsbc.service; do
  systemctl stop "$u" 2>/dev/null || true
  systemctl disable "$u" 2>/dev/null || true
done
systemctl reset-failed 2>/dev/null || true

log "removing unit files + polkit rule..."
rm -f /etc/systemd/system/rndrsbc@.service \
      "/etc/systemd/system/rndrsbc-${REAL_USER}.service" \
      /etc/systemd/system/rndrsbc.service \
      /etc/polkit-1/rules.d/10-rndrsbc-restart.rules
systemctl daemon-reload

log "killing stray engine processes..."
pkill -u "$REAL_USER" -f 'rndrsbc' 2>/dev/null || true
sleep 1

if [ "$WIPE" = "yes" ]; then
  log "WIPING deploy home $DEPLOY_HOME (--wipe)"
  rm -rf "$DEPLOY_HOME"
else
  if [ -f "$DEPLOY_HOME/config.json" ]; then
    cp "$DEPLOY_HOME/config.json" "$DEPLOY_HOME/config.json.reset-backup"
    log "config preserved at $DEPLOY_HOME/config.json.reset-backup"
  fi
  # Keep the deploy home but reset volatile state that can carry corruption.
  rm -rf "$DEPLOY_HOME/data" "$DEPLOY_HOME/cache" "$DEPLOY_HOME/registry" 2>/dev/null || true
fi

log "removing virtualenv + leftovers (including root-owned pip debris)..."
rm -rf "$VENV_DIR"
rm -rf "$REAL_HOME/.cache/pip"
rm -f /usr/local/bin/rndrsbc

log "reinstalling via install.sh (rndrsbc[pi] from PyPI, fresh unit, polkit rule)..."
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.sh" \
  --with-service --service-user "$REAL_USER" --deps
