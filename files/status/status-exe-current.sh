# status-exe-current.sh -- verify that each MainPID runs the deployed inode.

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

_check_exe() { # name unit expected
  local name="$1" unit="$2" expected="$3"
  local running="$_proc_root/$_pid/exe"
  if [ ! -e "$expected" ]; then
    _say "$name" "DRIFT: expected executable is missing: $expected"
    return 1
  fi
  if [ "$running" -ef "$expected" ]; then
    _say "$name" "OK: $unit MainPID $_pid runs the deployed executable"
    return 0
  fi
  if ! stat -L "$running" >/dev/null 2>&1; then
    _say "$name" "DRIFT: cannot inspect executable for $unit MainPID $_pid"
  else
    _say "$name" "DRIFT: $unit MainPID $_pid runs a different executable inode"
  fi
  return 1
}

{% for check in _item.status_proc_checks %}
if _resolve_mainpid {{ check.name | quote }} {{ check.unit | quote }} {{ check.manager | default(SYSTEMD_SCOPE | default('system')) | quote }}; then
  _applicable=1
  if ! _check_exe {{ check.name | quote }} {{ check.unit | quote }} {{ check.expected | quote }}; then _drift=1; fi
else
  _code=$?
  if [ "$_code" -eq 1 ]; then _drift=1; fi
fi
{% endfor %}

if [ "$_drift" -ne 0 ]; then exit 1; fi
if [ "$_applicable" -eq 0 ]; then exit 2; fi
exit 0
