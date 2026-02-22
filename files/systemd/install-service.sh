#!/bin/bash
set -e

USERMODE="${USERMODE:-false}"
SERVICE_NAME="${SERVICE_NAME:-$(basename "$(pwd)")}"
SERVICE_FILE="${SERVICE_FILE:-${SERVICE_NAME}}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVICE_SRC="${SERVICE_SRC:-${SCRIPT_DIR}/../etc/${SERVICE_FILE}.service}"

if [ "$USERMODE" = "true" ]; then
  SERVICE_DEST="${SERVICE_DEST:-${HOME}/.config/systemd/user/${SERVICE_NAME}.service}"
  SUDO="${SUDO:-false}"
  SYSTEMCTL="${SYSTEMCTL:-systemctl --user}"
else
  SERVICE_DEST="${SERVICE_DEST:-/etc/systemd/system/${SERVICE_NAME}.service}"
  SUDO="${SUDO:-sudo}"
  SYSTEMCTL="${SYSTEMCTL:-systemctl}"
fi

if [ "$SUDO" = "false" ]; then
  SUDO_CMD=""
else
  SUDO_CMD="$SUDO"
fi

if [ ! -f "$SERVICE_SRC" ]; then
  echo "Error: Service file not found: $SERVICE_SRC"
  exit 1
fi

mkdir -p "$(dirname "$SERVICE_DEST")"

NEED_RELOAD=false

if [ -L "$SERVICE_DEST" ]; then
  CURRENT_TARGET=$(readlink -f "$SERVICE_DEST")
  NEW_TARGET=$(readlink -f "$SERVICE_SRC")
  if [ "$CURRENT_TARGET" != "$NEW_TARGET" ]; then
    NEED_RELOAD=true
  fi
elif [ -e "$SERVICE_DEST" ]; then
  NEED_RELOAD=true
else
  NEED_RELOAD=true
fi

$SUDO_CMD ln -sf "$SERVICE_SRC" "$SERVICE_DEST"

if [ "$NEED_RELOAD" = true ]; then
  echo "Service file changed, reloading systemd daemon..."
  $SUDO_CMD $SYSTEMCTL daemon-reload
fi

$SUDO_CMD $SYSTEMCTL enable "$SERVICE_NAME"
echo "Service ${SERVICE_NAME} installed and enabled"
