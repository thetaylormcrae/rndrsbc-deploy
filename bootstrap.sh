#!/usr/bin/env bash
# rndrSBC deployment scaffold: create deploy home + default config.
set -euo pipefail

usage() { echo "usage: $0 --home <dir> [--config <json>]"; exit 1; }
HOME_DIR=""
CFG_SRC="$(dirname "$0")/examples/config.template.json"
while [ $# -gt 0 ]; do
  case "$1" in
    --home) HOME_DIR="$2"; shift 2;;
    --config) CFG_SRC="$2"; shift 2;;
    *) usage;;
  esac
done
[ -n "$HOME_DIR" ] || usage

mkdir -p "$HOME_DIR"/{data,plugins,registry}
if [ ! -f "$HOME_DIR/config.json" ]; then
  cp "$CFG_SRC" "$HOME_DIR/config.json"
  echo "created $HOME_DIR/config.json (edit to configure your frame)"
else
  echo "config.json already exists; leaving it alone"
fi
echo "deploy home ready: $HOME_DIR"
echo "Point RNDRSBC_HOME at it when running:"
echo "  export RNDRSBC_HOME=$HOME_DIR"
