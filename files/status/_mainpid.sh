_proc_root="${STATUS_PROC_ROOT:-/proc}"
_systemctl_bin="${STATUS_SYSTEMCTL:-systemctl}"
_applicable=0
_drift=0
_pid=""

_say() { printf '%-24s %s\n' "$1" "$2"; }

_resolve_mainpid() { # name unit manager
  local name="$1" unit="$2" manager="$3" state
  local -a args
  case "$manager" in
    user) args=(--user) ;;
    system) args=(--system) ;;
  esac

  if ! state="$("$_systemctl_bin" "${args[@]}" show "$unit" -p ActiveState --value 2>/dev/null)"; then
    _say "$name" "DRIFT: cannot query $manager unit $unit"
    return 1
  fi
  if [ "$state" != active ]; then
    _say "$name" "n/a: $unit is ${state:-unavailable}"
    return 2
  fi
  if ! _pid="$("$_systemctl_bin" "${args[@]}" show "$unit" -p MainPID --value 2>/dev/null)"; then
    _say "$name" "DRIFT: cannot resolve MainPID for $unit"
    return 1
  fi
  case "$_pid" in
    ''|0|*[!0-9]*)
      _say "$name" "n/a: $unit has no MainPID"
      return 2 ;;
  esac
  return 0
}
