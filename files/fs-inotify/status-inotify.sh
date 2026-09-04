# status-inotify.sh — per-user or per-unit inotify pool consumption as a
# status.sh reporter. usage.sh is the interactive top-consumers view; this
# is the one-glance pool answer for status.sh runs: the current user's TOTAL
# watch/instance consumption against the sysctls this playbook owns, the
# top consumers holding them, and drift at >=90% of the watch pool —
# exhaustion poisons every watcher on the user (daemons, opencode
# sessions, editors), not just one process, so pool pressure is drift
# even when each individual consumer looks healthy.
#
# --unit UNIT scopes the count to one systemd --user unit's cgroup: the
# service's own consumption only, never strays or other instances. It remains
# this pool owner's convenience view. An inactive unit reports no consumption
# (exit 0); unit liveness itself is other reporters' drift.
#
# Counting (same technique as usage.sh): a WATCH is one
# /proc/<pid>/fdinfo/<fd> "inotify wd:" line (~1KB kernel RAM each,
# non-swappable); an INSTANCE is one anon_inode:inotify fd.
#
# Exit per status.sh convention: 0 clean, 1 drift, 2 not-applicable.
# Test seams: STATUS_INOTIFY_PROC_ROOT (default /proc),
# STATUS_INOTIFY_SYSTEMCTL (default `systemctl --user`),
# STATUS_INOTIFY_TOP_N (default 5).

_root="${STATUS_INOTIFY_PROC_ROOT:-/proc}"
_topn="${STATUS_INOTIFY_TOP_N:-5}"
_systemctl="${STATUS_INOTIFY_SYSTEMCTL:-systemctl --user}"
_unit=""

_say() { printf '%-12s %s\n' "$1" "$2"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --unit) _unit="${2:?--unit needs a unit name}"; shift 2;;
    -n) _topn="${2:?-n needs a number}"; shift 2;;
    -h|--help)
      cat >&2 <<'EOF'
usage: status-inotify.sh [--unit UNIT] [-n N]
  Report inotify watch/instance consumption (read-only).
    --unit UNIT  scope to one systemd --user unit's cgroup (service only)
    -n N         number of consumers to list (default 5)
EOF
      exit 0;;
    *) echo "status-inotify.sh: unknown argument: $1 (try --help)" >&2; exit 2;;
  esac
done

_maxw="$(cat "$_root/sys/fs/inotify/max_user_watches" 2>/dev/null || echo 0)"
_maxi="$(cat "$_root/sys/fs/inotify/max_user_instances" 2>/dev/null || echo 0)"

# "watches instances" for one pid (unreadable procs count zero)
_count_pid() {
  _cp_w=0
  _cp_i=0
  for _fd in "$_root/$1"/fd/*; do
    case "$(readlink "$_fd" 2>/dev/null || true)" in
      anon_inode:inotify*)
        _cp_i=$((_cp_i + 1))
        _cp_n="$(grep -c '^inotify wd:' "$_root/$1/fdinfo/${_fd##*/}" 2>/dev/null || true)"
        _cp_w=$((_cp_w + ${_cp_n:-0}))
        ;;
    esac
  done
}

_scope=""
if [ -n "$_unit" ]; then
  _cgroup="$($_systemctl show "$_unit" -p ControlGroup --value 2>/dev/null || true)"
  if [ -z "${_cgroup:-}" ] || [ "${_cgroup:-}" = "/" ]; then
    _say unit "$_unit inactive; no consumption"
    exit 0
  fi
  _scope="$_unit"
fi

_myuid="$(id -u)"
_data=""
for _p in "$_root"/[0-9]*; do
  _pid="${_p##*/}"
  if [ -n "$_unit" ]; then
    _proc_cgroup="$(sed -n 's/^0:://p' "$_p/cgroup" 2>/dev/null || true)"
    case "$_proc_cgroup" in
      "$_cgroup"|"$_cgroup"/*) ;;
      *) continue ;;
    esac
  else
    _uid="$(awk '/^Uid:/{print $2; exit}' "$_p/status" 2>/dev/null || true)"
    [ "${_uid:-}" = "$_myuid" ] || continue
  fi
  _count_pid "$_pid"
  [ "$_cp_i" -gt 0 ] || continue
  _data="${_data}${_cp_w} ${_cp_i} ${_pid} $(cat "$_p/comm" 2>/dev/null || echo '?')
"
done

if [ -z "$_data" ]; then
  if [ -n "$_unit" ]; then
    _say unit "$_unit active but holds no inotify watches"
  else
    _say pool "OK: 0 watches, 0 instances, no inotify consumers"
  fi
  exit 0
fi

_totals="$(printf '%s' "$_data" | awk '{w+=$1; i+=$2; n++} END{printf "%d %d %d", w, i, n}')"
_tw="${_totals%% *}"
_rest="${_totals#* }"
_ti="${_rest%% *}"
_tn="${_rest#* }"

_pct=$(( _tw * 100 / (_maxw > 0 ? _maxw : 1) ))
_ipct=$(( _ti * 100 / (_maxi > 0 ? _maxi : 1) ))
_say pool "${_tw}/${_maxw} watches (${_pct}%), ${_ti}/${_maxi} instances (${_ipct}%), ${_tn} process(es)${_scope:+ — scope: ${_scope} cgroup (pool is user-wide)}"

printf '%s' "$_data" | sort -rn | head -n "$_topn" | while read -r _w _i _pid _comm; do
  _say top "${_w} watches, ${_i} inst — pid ${_pid} (${_comm})"
done

_drift=0
if [ "$_pct" -ge 90 ]; then
  _say result "DRIFT: watch pool at ${_pct}% — new watchers anywhere will hit ENOSPC (see usage.sh for the arsonists)"
  _drift=1
elif [ "$_ipct" -ge 90 ]; then
  _say result "DRIFT: instance pool at ${_ipct}% — inotify_init() will start failing"
  _drift=1
else
  _say result "OK"
fi
exit "$_drift"
