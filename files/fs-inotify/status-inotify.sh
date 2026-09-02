# status-inotify.sh — per-user inotify pool consumption as a status.sh
# reporter. usage.sh is the interactive top-consumers view; this is the
# one-glance pool answer for status.sh runs: the current user's TOTAL
# watch/instance consumption against the sysctls this playbook owns, the
# top consumers holding them, and drift at >=90% of the watch pool —
# exhaustion poisons every watcher on the user (daemons, opencode
# sessions, editors), not just one process, so pool pressure is drift
# even when each individual consumer looks healthy.
#
# Counting (same technique as usage.sh): a WATCH is one
# /proc/<pid>/fdinfo/<fd> "inotify wd:" line (~1KB kernel RAM each,
# non-swappable); an INSTANCE is one anon_inode:inotify fd. Same-UID
# processes only — no privileges needed or used.
#
# Exit per status.sh convention: 0 clean, 1 drift, 2 not-applicable.
# Test seams: STATUS_INOTIFY_PROC_ROOT (default /proc),
# STATUS_INOTIFY_TOP_N (default 5).

_root="${STATUS_INOTIFY_PROC_ROOT:-/proc}"
_topn="${STATUS_INOTIFY_TOP_N:-5}"
_myuid="$(id -u)"

_say() { printf '%-12s %s\n' "$1" "$2"; }

_maxw="$(cat "$_root/sys/fs/inotify/max_user_watches" 2>/dev/null || echo 0)"
_maxi="$(cat "$_root/sys/fs/inotify/max_user_instances" 2>/dev/null || echo 0)"

_data=""
for _p in "$_root"/[0-9]*; do
  _uid="$(awk '/^Uid:/{print $2; exit}' "$_p/status" 2>/dev/null || true)"
  [ "${_uid:-}" = "$_myuid" ] || continue
  _w=0
  _i=0
  for _fd in "$_p"/fd/*; do
    case "$(readlink "$_fd" 2>/dev/null || true)" in
      anon_inode:inotify*)
        _i=$((_i + 1))
        _n="$(grep -c '^inotify wd:' "$_p/fdinfo/${_fd##*/}" 2>/dev/null || true)"
        _w=$((_w + ${_n:-0}))
        ;;
    esac
  done
  [ "$_i" -gt 0 ] || continue
  _data="${_data}${_w} ${_i} ${_p##*/} $(cat "$_p/comm" 2>/dev/null || echo '?')
"
done

if [ -z "$_data" ]; then
  _say pool "OK: 0 watches, 0 instances, no inotify consumers"
  exit 0
fi

_totals="$(printf '%s' "$_data" | awk '{w+=$1; i+=$2; n++} END{printf "%d %d %d", w, i, n}')"
_tw="${_totals%% *}"
_rest="${_totals#* }"
_ti="${_rest%% *}"
_tn="${_rest#* }"

_pct=$(( _tw * 100 / (_maxw > 0 ? _maxw : 1) ))
_ipct=$(( _ti * 100 / (_maxi > 0 ? _maxi : 1) ))
_say pool "${_tw}/${_maxw} watches (${_pct}%), ${_ti}/${_maxi} instances (${_ipct}%), ${_tn} consumer(s)"

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
