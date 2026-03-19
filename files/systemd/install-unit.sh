#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "$ENV_BYPASS" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

UNIT_SRC="${UNIT_SRC:-$SCRIPT_DIR/../etc/${UNIT_NAME}.${UNIT_TYPE}}"
UNIT_DEST="${UNIT_DEST:-$UNIT_DIR/${UNIT_NAME}.${UNIT_TYPE}}"

mkdir -p "$(dirname "$UNIT_DEST")"
$SUDO_CMD ln -sf "$UNIT_SRC" "$UNIT_DEST"
$SUDO_CMD $SYSTEMCTL daemon-reload
$SUDO_CMD $SYSTEMCTL enable "$UNIT_NAME"
echo "Unit ${UNIT_NAME}.${UNIT_TYPE} installed and enabled"
