#!/bin/bash
# status-cacher.sh -- read-only status summary for the apt-cacher-rs daemon.
#
# Combines three views into one glanceable report:
#   - systemd state of apt-cacher-rs-git.service (activity, PID, uptime,
#     alias resolution)
#   - an HTTP probe of the web UI (status code + latency)
#   - the parsed dashboard: Daemon Status / Cache Statistics / the
#     operationally-important Metrics rows, plus the Mirrors / Clients /
#     Uncacheables tables. Rows that a given daemon version does not emit
#     degrade to "-".
#
# Strictly read-only: no restarts, no config writes, no cache mutation --
# safe to run while builds stream through the proxy.
#
# Usage:
#   status-cacher.sh                  # summary (default)
#   status-cacher.sh --logs           # the web UI /logs page
#   status-cacher.sh --journal [N]    # journalctl tail (default 20 lines)
#   status-cacher.sh --all            # summary + logs + journal
#   status-cacher.sh --watch SECONDS  # re-run the summary every N seconds
#   APT_CACHER_URL=http://host:3142/ status-cacher.sh   # other daemon
#
# Exit status: 0 reachable, 1 daemon down/unreachable, 2 usage error.
set -euo pipefail

UNIT="apt-cacher-rs-git.service"
ALIAS="apt-cacher-rs.service"
BASE="${APT_CACHER_URL:-http://127.0.0.1:3142/}"; BASE="${BASE%/}"

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print} NR>1 && !/^#/ {exit}' "$0"; exit "${1:-0}"; }

show_summary=0 show_logs=0 show_journal=0 journal_n=20 watch=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all)     show_summary=1 show_logs=1 show_journal=1 ;;
    --logs)    show_logs=1 ;;
    --journal) show_journal=1
               if [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]]; then journal_n="$2"; shift; fi ;;
    --watch)   [ $# -ge 2 ] && [[ "$2" =~ ^[0-9]+$ ]] || { echo "error: --watch needs a seconds argument" >&2; exit 2; }
               watch="$2"; shift ;;
    -h|--help) usage 0 ;;
    *)         echo "error: unknown argument: $1" >&2; usage 2 ;;
  esac
  shift
done
# No mode picked -> the default summary.
if [ "$show_summary$show_logs$show_journal" = "000" ]; then show_summary=1; fi

tmp="$(mktemp)"; tmp_err="$(mktemp)"
trap 'rm -f "$tmp" "$tmp_err"' EXIT

# fetch PATH -> body on stdout; nonzero exit + stderr message when the
# daemon cannot be reached.
fetch() {
  curl -sS -m 10 -o "$tmp" "$BASE$1" 2>"$tmp_err"
}

# --- HTML helpers -----------------------------------------------------------
# The dashboard is one long line. Split it into one <tr> row per line, keep
# only the rows of the named <h3> section, then render each row as
# tab-separated cells with tags stripped and entities decoded.
section_rows() {
  printf '%s' "$HTML" \
    | sed -e 's/<h3/\n<h3/g' -e 's/<tr>/\n<tr>/g' \
    | awk -v sec="$1" '
        /<h3[^>]*>/ { in_sec = ($0 ~ ("<h3[^>]*>" sec "</h3>")); next }
        in_sec && /^<tr>/ { print }' \
    | sed -e 's|</tr>.*||' -e 's/<\/td><td[^>]*>/\t/g' -e 's/<[^>]*>//g' \
          -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' \
          -e "s/&#x27;/'/g" -e 's/&#39;/'"'"'/g' -e 's/&amp;/\&/g'
}

# field SECTION LABEL -> the value cell of that exact label; "-" when the
# row is absent (older/newer daemon, renamed label).
field() {
  local v
  v="$(section_rows "$1" | awk -F'\t' -v k="$2" '$1 == k {print $2; exit}')" || true
  printf '%s' "${v:--}"
}

# table SECTION AWK_BODY -> rows of a <th>-headed table, skipping the
# header line; "(none)" when the table is empty or absent.
table() {
  local out
  out="$(section_rows "$1" | awk -F'\t' 'NR > 1 { print }')" || true
  if [ -z "$out" ]; then printf '  (none)\n'; else printf '%s\n' "$out" | awk -F'\t' "$2"; fi
}

# --- systemd ----------------------------------------------------------------
service_state() {
  local state pid since etime aliases declared verdict
  state="$(systemctl is-active "$UNIT" 2>/dev/null || true)"
  pid="$(systemctl show -p MainPID --value "$UNIT" 2>/dev/null || true)"
  since="$(systemctl show -p ActiveEnterTimestamp --value "$UNIT" 2>/dev/null || true)"
  etime=""
  if [ -n "$pid" ] && [ "$pid" != "0" ]; then
    etime="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  fi
  printf 'service  : %s (PID %s, up %s, since %s)\n' \
    "${state:-unknown}" "${pid:-?}" "${etime:-?}" "${since:-(not started)}"

  # Alias verdict: systemd's live view first, then the [Install] Alias=
  # declaration -- a declared-but-unlinked alias is a real finding.
  aliases="$(systemctl show -p Aliases --value "$UNIT" 2>/dev/null || true)"
  declared="$(systemctl cat "$UNIT" 2>/dev/null | awk -F= '/^Alias=/ {print $2}' || true)"
  if printf '%s' "$aliases" | grep -qw "$ALIAS"; then
    verdict="linked (active alias)"
  elif [ "$declared" = "$ALIAS" ]; then
    verdict="declared (Alias=) but NOT linked; sudo systemctl enable $UNIT recreates it"
  else
    verdict="not declared by this unit"
  fi
  printf 'alias    : %s -> %s\n' "$ALIAS" "$verdict"
}

# --- dashboard summary ------------------------------------------------------
summary() {
  local code latency
  service_state

  if ! meta="$(curl -sS -m 10 -o "$tmp" -w '%{http_code} %{time_total}' "$BASE/" 2>"$tmp_err")"; then
    printf 'probe    : FAIL %s (%s)\n' "$BASE/" "$(tr '\n' ' ' < "$tmp_err" | xargs)"
    echo "error: daemon unreachable at $BASE/ (is $UNIT running?)" >&2
    exit 1
  fi
  code="${meta%% *}"; latency="${meta#* }"
  if [ "$code" != "200" ]; then
    printf 'probe    : %s -> HTTP %s\n' "$BASE/" "$code"
    echo "error: dashboard returned HTTP $code" >&2
    exit 1
  fi
  printf 'probe    : %s -> %s in %ss\n' "$BASE/" "$code" "$latency"
  HTML="$(cat "$tmp")"

  printf 'daemon   : version %s\n' "$(field 'Daemon Status' 'Version')"
  printf '           started %s\n' "$(field 'Daemon Status' 'Start Time')"
  printf '           memory %s, db %s\n' \
    "$(field 'Daemon Status' 'Memory Usage')" "$(field 'Daemon Status' 'Database Size')"
  printf '           clients %s, upstream downloads %s, HTTPS tunnels %s\n' \
    "$(field 'Daemon Status' 'Connected Clients')" \
    "$(field 'Daemon Status' 'Active Upstream Downloads')" \
    "$(field 'Daemon Status' 'Active HTTPS Tunnels')"

  printf 'cache    : fetched %s, served %s, saved %s (%s)\n' \
    "$(field 'Cache Statistics' 'Fetched from Upstream')" \
    "$(field 'Cache Statistics' 'Served to Clients')" \
    "$(field 'Cache Statistics' 'Bandwidth Saved')" \
    "$(field 'Cache Statistics' 'Bandwidth Savings')"
  printf '           hit ratio %s\n' "$(field 'Cache Statistics' 'Cache Hit Ratio (persisted)')"
  printf '           files %s\n' "$(field 'Cache Statistics' 'Cached Files')"
  printf '           disk %s, free %s\n' \
    "$(field 'Cache Statistics' 'Total Disk Usage')" "$(field 'Cache Statistics' 'Free Disk Space')"

  printf 'health   : integrity mismatch %s, throttled %s\n' \
    "$(field Metrics 'Integrity Mismatch (rejected)')" \
    "$(field Metrics 'Integrity Throttled Resources')"
  printf '           cache I/O failures %s, db failures %s\n' \
    "$(field Metrics 'Cache I/O Failures')" "$(field Metrics 'DB Operation Failures')"
  printf '           rate-limit cancels %s, http timeouts %s\n' \
    "$(field Metrics 'Rate-Limit Cancellations (upstream / client)')" \
    "$(field Metrics 'HTTP Timeouts (upstream connect / upstream read / client header read / client header write / client body)')"
  printf '           uncacheable resources %s\n' "$(field 'Cache Statistics' 'Uncacheable Resources')"

  echo 'mirrors  : (name / last seen / disk)'
  table Mirrors '{printf "  %-30s %-21s %s\n", $1, $2, $8}'
  echo 'clients  : (ip / last seen / served / requests)'
  table Clients '{printf "  %-16s %-21s %-10s %s\n", $1, $2, $4, $5}'
  echo 'uncacheables  : (host / path)'
  table Uncacheables '{printf "  %s %s\n", $1, $2}'
}

logs() {
  if ! fetch /logs; then
    echo "error: cannot fetch $BASE/logs ($(tr '\n' ' ' < "$tmp_err" | xargs))" >&2
    exit 1
  fi
  echo "--- $BASE/logs ---"
  # <pre class="log"> holds the entries verbatim.
  sed -n '/<pre class="log">/,/<\/pre>/p' "$tmp" \
    | sed -e '1s/.*<pre class="log">//' -e '$s|</pre>.*||' \
          -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&amp;/\&/g'
}

journal() {
  local out
  echo "--- journal: $UNIT (last $journal_n) ---"
  if ! out="$(journalctl -u "$UNIT" --no-pager -n "$journal_n" 2>&1)"; then
    echo "warning: journalctl failed: $out" >&2
    return 0
  fi
  printf '%s\n' "$out"
}

render() {
  [ "$show_summary" = 1 ] && summary
  [ "$show_logs" = 1 ] && logs
  [ "$show_journal" = 1 ] && journal
  return 0
}

if [ "$watch" != "0" ]; then
  while true; do
    clear 2>/dev/null || true
    render || true   # keep watching through transient failures
    printf -- '-- %s (refresh %ss, Ctrl-C to quit) --\n' "$(date '+%H:%M:%S')" "$watch"
    sleep "$watch"
  done
else
  render
fi
