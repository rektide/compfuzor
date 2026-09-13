#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "${ENV_BYPASS:-}" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

_bypass_start=false
_bypass_link=false
_bypass_enable=false
_explicit_strategy=""
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
      _explicit_strategy=copy
      ;;
    --link)
      _explicit_strategy=link
      ;;
    *)
      _pass_through+=("$arg")
      ;;
  esac
done

UNIT_SRC="${UNIT_SRC:-$SCRIPT_DIR/../etc/${UNIT_TEMPLATE}.${UNIT_TYPE}}"
UNIT_DEST="${UNIT_DEST:-$UNIT_DIR/${UNIT_TEMPLATE}.${UNIT_TYPE}}"

if [ -n "$_explicit_strategy" ]; then
  _strategy="$_explicit_strategy"
elif [ -n "${SYSTEMD_COPY:-}" ] || [ -n "${SYSTEMD_INSTALL_COPY:-}" ]; then
  _strategy=copy
else
  _strategy="${UNIT_LINK_DEFAULT:-link}"
fi

# SYSTEMD_BYPASS_* remains a temporary soak alias for generated artifacts.
if [ "$_bypass_link" = true ] || [ -n "${COMPFUZOR_SYSTEMD_LINK_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_LINK:-}" ]; then
  echo "Bypassed linking ${UNIT_DEST}"
else
  if [ -x "$(dirname "$0")/links.ts" ]; then
    # Publication is delegated to links.ts: the LINKS subsystem owns both
    # accepted unit representations. UNIT_LINK_ID is baked at generation and
    # matches the record id; ${HOME} stays literal for user scope.
    # Privilege routing is automatic: the default auto mode probes the dest
    # per record and escalates only unwritable ones through sudo, so
    # user-scope dests mutate directly.
    if [ -n "$_explicit_strategy" ] || [ -n "${SYSTEMD_COPY:-}" ] || [ -n "${SYSTEMD_INSTALL_COPY:-}" ]; then
      "$(dirname "$0")/links.ts" apply --id "$UNIT_LINK_ID" --strategy "$_strategy"
    else
      # No explicit selection lets LINKS preserve either currently healthy
      # representation and use the compiled record default only when missing.
      "$(dirname "$0")/links.ts" apply --id "$UNIT_LINK_ID"
    fi
  else
    # No links.ts (LINKS_BYPASS, or a deployment predating the LINKS
    # subsystem): retain direct copy/link behavior using the same selection.
    $SUDO_CMD mkdir -p "$(dirname "$UNIT_DEST")"
    if [ "$_strategy" = copy ]; then
      $SUDO_CMD cp --remove-destination -f "$UNIT_SRC" "$UNIT_DEST"
      echo "Copied ${UNIT_SRC} -> ${UNIT_DEST}"
    else
      $SUDO_CMD ln -sf "$UNIT_SRC" "$UNIT_DEST"
      echo "Linked ${UNIT_SRC} -> ${UNIT_DEST}"
    fi
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
  # Always enable a fully-typed unit name: a bare name makes systemctl
  # default to .service, which enables the WRONG unit for socket/timer/
  # ... installs (and fails outright when that service isn't linked).
  # Hand-authored callers that already carry the suffix are passed through.
  case "$target" in
    *.${UNIT_TYPE}) unit_ref="$target" ;;
    *) unit_ref="${target}.${UNIT_TYPE}" ;;
  esac
  if [ "$_bypass_start" = true ] || [ -n "${COMPFUZOR_SYSTEMD_START_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_START:-}" ]; then
    $SUDO_CMD $SYSTEMCTL enable "${_pass_through[@]+"${_pass_through[@]}"}" "$unit_ref"
  else
    $SUDO_CMD $SYSTEMCTL enable --now "${_pass_through[@]+"${_pass_through[@]}"}" "$unit_ref"
  fi
  echo "Unit ${unit_ref} enabled"
done
