# usage.sh — inotify usage report: per-user watch/instance consumption and the
# top (or bottom) consumers holding watches. Read-only.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration, so this file has
# no shebang of its own. The body is rendered as a Jinja template, so the
# bash array-length idiom in pid_inotify escapes its leading brace
# (dollar-brace-hash) so Jinja does not read it as a comment delimiter.
#
# Without flags it reports the CURRENT USER only -- no privileges needed,
# since you can read your own processes' /proc/<pid>/fdinfo. Pass --sudo
# to elevate and enumerate every user plus a system-wide total.
#
# "What a consumer is using" is its cwd (the tree being watched) plus
# watch/instance counts. A WATCH ~= one watched inode (~1KB of kernel
# RAM, non-swappable); an INSTANCE is one inotify_init() fd that holds
# many watches. The limit that actually binds in practice is watches.

usage() {
  cat >&2 <<'EOF'
usage: usage.sh [--no-color] [--sudo] [--user USER] [-n N] [--bottom] [-h]
  Report inotify watch/instance consumption for the current user, or
  system-wide with --sudo. Read-only.
    --no-color   plain output (auto-detected otherwise)
    --sudo       elevate to enumerate every user + system totals
    --user USER  focus on USER (needs --sudo if not you)
    -n N         number of consumers to list (default 5)
    --bottom     list LOW-watch consumers first (surfaces stalled processes)
    -h, --help   show this help
EOF
}

USE_SUDO=0
FOCUS_USER=""
COLOR="${COLOR:-auto}"
TOP_N=5
SORTFLAGS="-rn"

while [ $# -gt 0 ]; do
  case "$1" in
    --no-color) COLOR=0; shift;;
    --sudo)     USE_SUDO=1; shift;;
    --user)     FOCUS_USER="${2:?--user needs a username}"; shift 2;;
    --user=*)   FOCUS_USER="${1#--user=}"; shift;;
    -n)         TOP_N="${2:?-n needs a number}"; shift 2;;
    --bottom)   SORTFLAGS="-n"; shift;;
    -h|--help)  usage; exit 0;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2;;
  esac
done

if [ "$COLOR" = auto ]; then
  [ -t 1 ] && COLOR=1 || COLOR=0
fi
if [ "$COLOR" = 1 ]; then
  HDR=$'\033[1;36m'; DIM=$'\033[2m'; RST=$'\033[0m'
  RED=$'\033[1;31m'; GRN=$'\033[1;32m'; YLW=$'\033[1;33m'
else
  HDR=""; DIM=""; RST=""; RED=""; GRN=""; YLW=""
fi

hr() { printf '\n%s== %s ==%s\n' "$HDR" "$*" "$RST"; }

SUDO=""
[ "$USE_SUDO" = 1 ] && SUDO="sudo"

MY_UID="$(id -u)"
MAX_WATCHES="$(cat /proc/sys/fs/inotify/max_user_watches 2>/dev/null || echo 0)"
MAX_INSTANCES="$(cat /proc/sys/fs/inotify/max_user_instances 2>/dev/null || echo 0)"

FOCUS_UID=""
if [ -n "$FOCUS_USER" ]; then
  FOCUS_UID="$(id -u "$FOCUS_USER" 2>/dev/null || true)"
  [ -n "$FOCUS_UID" ] || { echo "no such user: $FOCUS_USER" >&2; exit 2; }
fi

# colored "used/max (pct%)" -- used only on free-form lines, never padded
ratio() {
  local used=$1 max=$2 pct
  if ! [ "$max" -gt 0 ] 2>/dev/null; then printf '%s%s/%s%s' "$DIM" "$used" "$max" "$RST"; return; fi
  pct=$(( used * 100 / max ))
  local c="$GRN"
  [ "$pct" -ge 70 ] && c="$YLW"
  [ "$pct" -ge 90 ] && c="$RED"
  printf '%s%d/%d (%d%%)%s' "$c" "$used" "$max" "$pct" "$RST"
}

# trailing colored pressure token (safe after a padded row)
pressure() {
  local used=$1 max=$2 pct
  if ! [ "$max" -gt 0 ] 2>/dev/null; then printf '%s?%s' "$DIM" "$RST"; return; fi
  pct=$(( used * 100 / max ))
  if   [ "$pct" -ge 90 ]; then printf '%sMAX %d%%%s' "$RED"  "$pct" "$RST"
  elif [ "$pct" -ge 70 ]; then printf '%shi %d%%%s'   "$YLW"  "$pct" "$RST"
  else                         printf '%sok%s'       "$GRN"        "$RST"; fi
}

uid_name() { local n; n="$(getent passwd "$1" | cut -d: -f1)"; printf '%s' "${n:-$1}"; }

# emit "watches instances" for one pid (uses $SUDO to read others' procs)
pid_inotify() {
  local pid=$1 fddir="/proc/$pid/fd" base tgt
  local ino=()
  [ -d "$fddir" ] || { echo "0 0"; return; }
  while IFS= read -r base; do
    tgt="$($SUDO readlink "$fddir/$base" 2>/dev/null || true)"
    case "$tgt" in anon_inode:inotify*) ino+=("$base");; esac
  done < <(ls -1 "$fddir" 2>/dev/null)
  [ "${{ "{" }}#ino[@]}" -gt 0 ] || { echo "0 0"; return; }
  local fdinfo_files=() f watches instances=${{ "{" }}#ino[@]}
  for f in "${ino[@]}"; do fdinfo_files+=("/proc/$pid/fdinfo/$f"); done
  watches="$($SUDO awk '/^inotify wd:/{c++} END{print c+0}' "${fdinfo_files[@]}" 2>/dev/null || echo 0)"
  echo "${watches:-0} ${instances}"
}

# gather "pid uid watches instances" for pids in scope
gather() {
  local p pid uid w i
  for p in /proc/[0-9]*; do
    pid="${p##*/}"
    uid="$(awk '/^Uid:/{print $2; exit}' "$p/status" 2>/dev/null)" || continue
    [ -n "${uid:-}" ] || continue
    if [ -n "$FOCUS_UID" ]; then
      [ "$uid" = "$FOCUS_UID" ] || continue
    elif [ "$USE_SUDO" != 1 ]; then
      [ "$uid" = "$MY_UID" ] || continue
    fi
    IFS=' ' read -r w i <<<"$(pid_inotify "$pid")"
    [ "${w:-0}" = 0 ] && [ "${i:-0}" = 0 ] && continue
    echo "$pid $uid ${w:-0} ${i:-0}"
  done
}

DATA="$(gather || true)"

if [ -z "$DATA" ]; then
  hr "consumers"
  printf '  %snone in scope%s\n' "$DIM" "$RST"
  exit 0
fi

# ---- usage summary
if [ "$USE_SUDO" = 1 ]; then
  hr "usage by user"
  printf '  %-14s %10s %10s %6s   %s\n' "USER" "WATCHES" "INST" "PROCS" "PRESSURE"
  printf '%s' "$DATA" | awk '{w[$2]+=$3; i[$2]+=$4; n[$2]++}
    END{ for (u in w) printf "%s %d %d %d\n", u, w[u], i[u], n[u] }' \
    | sort -k2 -rn | while read -r u w i n; do
      printf '  %-14s %10d %10d %6d   %s\n' "$(uid_name "$u")" "$w" "$i" "$n" "$(pressure "$w" "$MAX_WATCHES")"
    done
  sysw="$(printf '%s' "$DATA" | awk '{s+=$3} END{print s+0}')"
  sysi="$(printf '%s' "$DATA" | awk '{s+=$4} END{print s+0}')"
  sysn="$(printf '%s\n' "$DATA" | wc -l | tr -d ' ')"
  printf '  %s%-14s %10d %10d %6d   system totals%s\n' "$DIM" "TOTAL" "$sysw" "$sysi" "$sysn" "$RST"
else
  who="${FOCUS_USER:-$(id -un)}"
  hr "usage: ${who} (uid ${FOCUS_UID:-$MY_UID})"
  w="$(printf '%s' "$DATA" | awk '{s+=$3} END{print s+0}')"
  i="$(printf '%s' "$DATA" | awk '{s+=$4} END{print s+0}')"
  n="$(printf '%s\n' "$DATA" | wc -l | tr -d ' ')"
  printf '  watches:   %s   across %d proc(s)\n' "$(ratio "$w" "$MAX_WATCHES")" "$n"
  printf '  instances: %s\n' "$(ratio "$i" "$MAX_INSTANCES")"
fi

# ---- top/bottom N consumers
scope="you"; [ "$USE_SUDO" = 1 ] && scope="system"; [ -n "$FOCUS_UID" ] && scope="$(uid_name "$FOCUS_UID")"
dir="top"; [ "$SORTFLAGS" = "-n" ] && dir="bottom"
hr "${dir} ${TOP_N} consumers by watches (scope: $scope)"
printf '  %9s %5s %-9s %-18s %s\n' "WATCHES" "INST" "PID" "COMMAND" "CWD (what's watched)"
printf '%s' "$DATA" | sort -k3 "$SORTFLAGS" | head -n "$TOP_N" | while read -r pid uid w i; do
  comm="$(cat "/proc/$pid/comm" 2>/dev/null || $SUDO cat "/proc/$pid/comm" 2>/dev/null || echo "?")"
  cwd="$($SUDO readlink "/proc/$pid/cwd" 2>/dev/null || readlink "/proc/$pid/cwd" 2>/dev/null || echo "?")"
  printf '  %9d %5d %-9s %-18s %s\n' "$w" "$i" "$pid" "${comm:0:18}" "$cwd"
done
echo
