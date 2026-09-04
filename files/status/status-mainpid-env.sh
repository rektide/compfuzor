# status-mainpid-env.sh -- compare selected live MainPID environment entries.
# Expected values are baked into this generated reporter and must not contain
# secrets. Output deliberately names variables without printing their values.

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

_check_env() { # name unit key expected
  local name="$1" unit="$2" key="$3" expected="$4" code
  local environ="$_proc_root/$_pid/environ"
  if grep -zFqx -- "$key=$expected" "$environ" 2>/dev/null; then
    _say "$name" "OK: $unit MainPID $_pid has expected $key"
    return 0
  else
    code=$?
  fi
  if [ "$code" -eq 1 ]; then
    _say "$name" "DRIFT: $unit MainPID $_pid is missing or differs for $key"
  else
    _say "$name" "DRIFT: cannot inspect $key in $unit MainPID $_pid"
  fi
  return 1
}

{% for check in _item.status_proc_checks %}
if _resolve_mainpid {{ check.name | quote }} {{ check.unit | quote }} {{ check.manager | default(SYSTEMD_SCOPE | default('system')) | quote }}; then
  _applicable=1
{% for expected in check.expected | dict2items %}
  if ! _check_env {{ check.name | quote }} {{ check.unit | quote }} {{ expected.key | quote }} {{ expected.value | string | quote }}; then _drift=1; fi
{% endfor %}
else
  _code=$?
  if [ "$_code" -eq 1 ]; then _drift=1; fi
fi
{% endfor %}

if [ "$_drift" -ne 0 ]; then exit 1; fi
if [ "$_applicable" -eq 0 ]; then exit 2; fi
exit 0
