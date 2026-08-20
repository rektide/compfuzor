# guard-refusals.sh -- which clients/paths is the root_files guard refusing?
#
# The daemon logs every refused watch as a send_error_response line:
#   <ts>: [client=N:stm=...:pid=PID] send_error_response: ["watch"|"watch-project", "<path>"],
#         failed: ... None of the files listed in global config root_files ...
# Both refusal paths carry that signature text (watch-project walks UP from
# the requested path for a marker; plain watch checks the dir itself).
#
# This parses those lines out of the daemon log and aggregates them by client
# process and by path. The refused client only sees a JSON error -- and the
# CLI exits 0 on it -- so background services (e.g. an editor probing
# ~/.config) retry silently; this names them.
#
# Window: the whole current log, i.e. since the last takeover.sh trim or
# daemon restart. Not a status.sh reporter; informational, always exits 0
# (2 if the log is unreadable). Test seam: WATCHMAN_LOG.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.

_log="${WATCHMAN_LOG:-${HOME}/.local/var/lib/watchman-main/log}"
_topn=20

usage() {
  cat >&2 <<'EOF'
usage: guard-refusals.sh [-n N] [-h]
  Aggregate root_files guard refusals from the watchman daemon log:
  window, offending clients (with comm/cmdline), requested paths.
    -n N   paths to list (default 20)
    -h     this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n) _topn="${2:?-n needs a number}"; shift 2;;
    -n*) _topn="${1#-n}"; shift;;
    -h|--help) usage; exit 0;;
    *) printf 'guard-refusals.sh: unknown option: %s\n' "$1" >&2; exit 2;;
  esac
done

[ -r "$_log" ] || { printf 'guard-refusals.sh: no readable log at %s\n' "$_log" >&2; exit 2; }

# ts (date + hh:mm:ss) | pid | command | path
_hits="$(grep -a 'send_error_response.*None of the files listed in global config root_files' "$_log" \
  | sed -En 's/^([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]+),[0-9]+: \[client=[0-9]+:stm=[0-9]+:pid=([0-9]+)\] send_error_response: \["([^"]+)", "([^"]+)"\].*$/\1|\2|\3|\4/p' || true)"

if [ -z "$_hits" ]; then
  printf 'no guard refusals in %s\n' "$_log"
  exit 0
fi

_n="$(printf '%s\n' "$_hits" | wc -l | tr -d ' ')"
_first="$(printf '%s\n' "$_hits" | head -1 | cut -d'|' -f1)"
_last="$(printf '%s\n' "$_hits" | tail -1 | cut -d'|' -f1)"
printf '%s guard refusal(s) in %s\nwindow: %s .. %s (since last trim/restart)\n\n' "$_n" "$_log" "$_first" "$_last"

printf 'by client (live pids resolve to comm/cmdline):\n'
printf '%s\n' "$_hits" | cut -d'|' -f2 | sort | uniq -c | sort -rn | while read -r _c _p; do
  _comm="$(cat "/proc/$_p/comm" 2>/dev/null || true)"
  _cmdl="$(tr '\0' ' ' 2>/dev/null </proc/$_p/cmdline || true)"
  _cmdl="${_cmdl% }"
  _who="${_comm:-<gone>}"
  [ -n "$_cmdl" ] && _who="$_who  ${_cmdl:0:76}"
  printf '  %5d  pid %-9s %s\n' "$_c" "$_p" "$_who"
done

printf '\nby path (fix: add a marker, e.g. touch <dir>/.watch, or watch the repo dir):\n'
printf '%s\n' "$_hits" | cut -d'|' -f3,4 | tr '|' ' ' | sort | uniq -c | sort -rn | head -n "$_topn" | while read -r _c _cmd _path; do
  printf '  %5d  %-14s %s\n' "$_c" "$_cmd" "$_path"
done
