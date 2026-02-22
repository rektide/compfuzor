#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# source envs, using envdefault if available to not override any variables the shell already has set
[ -n "$ENV_BYPASS" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

set -e

USERMODE="${USERMODE:-false}"
UNIT_TYPE="${UNIT_TYPE:-service}"
UNIT_NAME="${UNIT_NAME:-${NAME:-$(basename "$(pwd)")}}"
UNIT_SUFFIX="${UNIT_SUFFIX:-}"
UNIT_FILE="${UNIT_FILE:-${UNIT_NAME}${UNIT_SUFFIX:+.$UNIT_SUFFIX}}"

UNIT_SRC="${UNIT_SRC:-${SCRIPT_DIR}/../etc/${UNIT_FILE}.${UNIT_TYPE}}"

if [ "$USERMODE" = "true" ]; then
  UNIT_DEST="${UNIT_DEST:-${HOME}/.config/systemd/user/${UNIT_NAME}.${UNIT_TYPE}}"
  SUDO="${SUDO:-false}"
  SYSTEMCTL="${SYSTEMCTL:-systemctl --user}"
else
  UNIT_DEST="${UNIT_DEST:-/etc/systemd/system/${UNIT_NAME}.${UNIT_TYPE}}"
  SUDO="${SUDO:-sudo}"
  SYSTEMCTL="${SYSTEMCTL:-systemctl}"
fi

if [ "$SUDO" = "false" ]; then
  SUDO_CMD=""
else
  SUDO_CMD="$SUDO"
fi

if [ ! -f "$UNIT_SRC" ]; then
  echo "Error: Unit file not found: $UNIT_SRC"
  exit 1
fi

mkdir -p "$(dirname "$UNIT_DEST")"

NEED_RELOAD=false

if [ -L "$UNIT_DEST" ]; then
  CURRENT_TARGET=$(readlink -f "$UNIT_DEST")
  NEW_TARGET=$(readlink -f "$UNIT_SRC")
  if [ "$CURRENT_TARGET" != "$NEW_TARGET" ]; then
    NEED_RELOAD=true
  fi
elif [ -e "$UNIT_DEST" ]; then
  NEED_RELOAD=true
else
  NEED_RELOAD=true
fi

$SUDO_CMD ln -sf "$UNIT_SRC" "$UNIT_DEST"

if [ "$NEED_RELOAD" = true ]; then
  echo "Unit file changed, reloading systemd daemon..."
  $SUDO_CMD $SYSTEMCTL daemon-reload
fi

$SUDO_CMD $SYSTEMCTL enable "$UNIT_NAME"
echo "Unit ${UNIT_NAME}.${UNIT_TYPE} installed and enabled"
