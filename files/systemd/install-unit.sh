#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "$ENV_BYPASS" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

UNIT_SRC="${UNIT_SRC:-$SCRIPT_DIR/../etc/${UNIT_TEMPLATE}.${UNIT_TYPE}}"
UNIT_DEST="${UNIT_DEST:-$UNIT_DIR/${UNIT_TEMPLATE}.${UNIT_TYPE}}"

mkdir -p "$(dirname "$UNIT_DEST")"
$SUDO_CMD ln -sf "$UNIT_SRC" "$UNIT_DEST"
$SUDO_CMD $SYSTEMCTL daemon-reload

if [ -z "$UNIT_ENABLE_TARGETS" ]; then
  echo "Template ${UNIT_TEMPLATE}.${UNIT_TYPE} installed (no instances to enable)"
  exit 0
fi

_bypass_start=false
_pass_through=()
for arg in "$@"; do
  if [ "$arg" = "--bypass-start" ]; then
    _bypass_start=true
  else
    _pass_through+=("$arg")
  fi
done

for target in $UNIT_ENABLE_TARGETS; do
  if [ "$_bypass_start" = true ] || [ -n "$SYSTEMD_BYPASS_START" ]; then
    $SUDO_CMD $SYSTEMCTL enable "${_pass_through[@]+"${_pass_through[@]}"}" "$target"
  else
    $SUDO_CMD $SYSTEMCTL enable --now "${_pass_through[@]+"${_pass_through[@]}"}" "$target"
  fi
  echo "Unit ${target}.${UNIT_TYPE} enabled"
done
