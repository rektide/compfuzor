#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "${ENV_BYPASS:-}" ] || [ ! -f "$SCRIPT_DIR/../env.export" ] || source <(command -v envdefault >/dev/null && envdefault "$SCRIPT_DIR/../env.export" || cat "$SCRIPT_DIR/../env.export")

UNIT_DIR="${UNIT_DIR:-${SYSTEMD_UNIT_DIR:-/etc/systemd/system}}"
SYSTEMCTL="${SYSTEMCTL:-systemctl}"
SUDO_CMD="${SUDO_CMD:-sudo}"
SYSTEMD_DROPIN_MATCH="${SYSTEMD_DROPIN_MATCH:-name}"

# Entries are: name|target|unit_dir|systemctl|sudo_cmd
DROPINS=(
{{ _dropin_rows }}
)

_bypass_link=false
_copy=false
_filter=""
for arg in "$@"; do
  case "$arg" in
    --bypass-link|--skip-link)
      _bypass_link=true
      ;;
    --copy)
      _copy=true
      ;;
    --bypass-enable|--skip-enable|--bypass-start|--skip-start)
      ;;
    *)
      [ -n "$_filter" ] || _filter="$arg"
      ;;
  esac
done

matches_dropin() {
  local name="$1"
  local target="$2"
  [ -n "$_filter" ] || return 0
  case "$SYSTEMD_DROPIN_MATCH" in
    target)
      case "$target" in $_filter) return 0 ;; esac
      ;;
    any|all|name,target|target,name)
      case "$name" in $_filter) return 0 ;; esac
      case "$target" in $_filter) return 0 ;; esac
      ;;
    *)
      case "$name" in $_filter) return 0 ;; esac
      ;;
  esac
  return 1
}

if [ -n "$_filter" ]; then
  _has_match=false
  for _row in "${DROPINS[@]}"; do
    IFS='|' read -r _name _target _unit_dir _systemctl _sudo_cmd <<< "$_row"
    if matches_dropin "$_name" "$_target"; then
      _has_match=true
      break
    fi
  done
  if [ "$_has_match" != true ]; then
    echo "No drop-in matched '${_filter}', installing all drop-ins"
    _filter=""
  fi
fi

declare -A _reloads=()
for _row in "${DROPINS[@]}"; do
  IFS='|' read -r _name _target _unit_dir _systemctl _sudo_cmd <<< "$_row"
  matches_dropin "$_name" "$_target" || continue

  _unit_dir="${_unit_dir:-$UNIT_DIR}"
  _systemctl="${_systemctl:-$SYSTEMCTL}"
  _sudo_cmd="${_sudo_cmd:-$SUDO_CMD}"
  [ "$_sudo_cmd" = "-" ] && _sudo_cmd=""
  _src="$SCRIPT_DIR/../etc/${_target}.d/${_name}.conf"
  _dest="${_unit_dir}/${_target}.d/${_name}.conf"

  # SYSTEMD_BYPASS_LINK remains a temporary soak alias for generated artifacts.
  if [ "$_bypass_link" = true ] || [ -n "${COMPFUZOR_SYSTEMD_LINK_BYPASS:-}" ] || [ -n "${SYSTEMD_BYPASS_LINK:-}" ]; then
    echo "Bypassed linking ${_dest}"
    continue
  fi

  $_sudo_cmd mkdir -p "$(dirname "$_dest")"
  if [ "$_copy" = true ] || [ -n "${SYSTEMD_COPY:-}" ] || [ -n "${SYSTEMD_INSTALL_COPY:-}" ]; then
    $_sudo_cmd cp --remove-destination -f "$_src" "$_dest"
    echo "Copied ${_src} -> ${_dest}"
  else
    $_sudo_cmd ln -sf "$_src" "$_dest"
    echo "Linked ${_src} -> ${_dest}"
  fi
  _reloads["${_sudo_cmd}|${_systemctl}"]=1
done

for _reload in "${!_reloads[@]}"; do
  IFS='|' read -r _sudo_cmd _systemctl <<< "$_reload"
  $_sudo_cmd $_systemctl daemon-reload
done
