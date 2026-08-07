#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "${ENV_BYPASS:-}" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

_bypass_start=false
_bypass_link=false
_bypass_enable=false
_copy=false
_pass_through=()
for arg in "$@"; do
  case "$arg" in
    --bypass-start|--skip-start)
      _bypass_start=true
      ;;
    --bypass-link|--skip-link)
      _bypass_link=true
      ;;
    --bypass-enable|--skip-enable)
      _bypass_enable=true
      ;;
    --copy)
      _copy=true
      ;;
    *)
      _pass_through+=("$arg")
      ;;
  esac
done

UNIT_SRC="${UNIT_SRC:-$SCRIPT_DIR/../etc/${UNIT_TEMPLATE}.${UNIT_TYPE}}"
UNIT_DEST="${UNIT_DEST:-$UNIT_DIR/${UNIT_TEMPLATE}.${UNIT_TYPE}}"

# SYSTEMD_BYPASS_* remains a temporary soak alias for generated artifacts.
if [ "$_bypass_link" = true ] || [ -n "${COMPFUZOR_SYSTEMD_LINK_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_LINK:-}" ]; then
  echo "Bypassed linking ${UNIT_DEST}"
else
  mkdir -p "$(dirname "$UNIT_DEST")"
  if [ "$_copy" = true ] || [ -n "${SYSTEMD_COPY:-}" ] || [ -n "${SYSTEMD_INSTALL_COPY:-}" ]; then
    $SUDO_CMD cp --remove-destination -f "$UNIT_SRC" "$UNIT_DEST"
    echo "Copied ${UNIT_SRC} -> ${UNIT_DEST}"
  else
    $SUDO_CMD ln -sf "$UNIT_SRC" "$UNIT_DEST"
    echo "Linked ${UNIT_SRC} -> ${UNIT_DEST}"
  fi
  $SUDO_CMD $SYSTEMCTL daemon-reload
fi

if [ -z "$UNIT_ENABLE_TARGETS" ]; then
  echo "Template ${UNIT_TEMPLATE}.${UNIT_TYPE} installed (no instances to enable)"
  exit 0
fi

if [ "$_bypass_enable" = true ] || [ -n "${COMPFUZOR_SYSTEMD_ENABLE_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_ENABLE:-}" ]; then
  echo "Bypassed enabling ${UNIT_TEMPLATE}.${UNIT_TYPE}"
  exit 0
fi

for target in $UNIT_ENABLE_TARGETS; do
  if [ "$_bypass_start" = true ] || [ -n "${COMPFUZOR_SYSTEMD_START_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_START:-}" ]; then
    $SUDO_CMD $SYSTEMCTL enable "${_pass_through[@]+"${_pass_through[@]}"}" "$target"
  else
    $SUDO_CMD $SYSTEMCTL enable --now "${_pass_through[@]+"${_pass_through[@]}"}" "$target"
  fi
  echo "Unit ${target}.${UNIT_TYPE} enabled"
done
