# status-exe-current.sh -- verify that each MainPID runs the deployed inode.

{% include "status/_mainpid.sh" %}

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
