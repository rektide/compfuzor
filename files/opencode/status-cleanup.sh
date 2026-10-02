# status-cleanup.sh — report leaked OpenCode native libraries and timer state.
#
# Dry-runs bin/cleanup-tmp.sh with the same eligibility window the
# opencode-cleanup-tmp.timer applies (default --min-age 0s), so status mirrors
# exactly what the next timer run would delete. Eligible inactive libraries
# count as drift: the timer should reap them, so a persistently non-zero count
# means the timer is not running (or dependency churn outruns it).
#
# Also reports whether the cleanup timer is enabled and active in the user
# manager when one is reachable (--no-timer skips that half).
#
# Exit per status.sh convention: 0 clean, 1 drift, 2 not-applicable/usage.
#
# This is a compfuzor _bin body: files/_bin supplies the shebang,
# `set -euo pipefail`, env loading, and option restoration.

cleanup="${DIR}/bin/cleanup-tmp.sh"
timer="{{ opencodeCleanupTimer.SYSTEMD_TIMER }}.timer"
[ -x "$cleanup" ] || exit 2

min_age=0s
tmp_dir=""
check_timer=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --min-age)
      [ "$#" -ge 2 ] || { printf 'status-cleanup.sh: --min-age needs a duration\n' >&2; exit 2; }
      min_age=$2
      shift 2 ;;
    --tmp-dir)
      [ "$#" -ge 2 ] || { printf 'status-cleanup.sh: --tmp-dir needs a path\n' >&2; exit 2; }
      tmp_dir=$2
      shift 2 ;;
    --no-timer)
      check_timer=0
      shift ;;
    -h|--help)
      cat <<'EOF'
usage: status-cleanup.sh [--min-age DURATION] [--tmp-dir DIR] [--no-timer]
  Dry-run bin/cleanup-tmp.sh with the timer's eligibility window and report the
  eligible leaked native libraries plus opencode-cleanup-tmp.timer's unit state.
EOF
      exit 0 ;;
    *)
      printf 'status-cleanup.sh: unknown option: %s\n' "$1" >&2
      exit 2 ;;
  esac
done

args=(--min-age "$min_age")
if [ -n "$tmp_dir" ]; then
  args+=(--tmp-dir "$tmp_dir")
fi

drift=0

# dry-run evidence first: eligible lines plus the summary come straight from
# cleanup-tmp.sh; the verdict below only interprets them
if ! out="$("$cleanup" "${args[@]}" 2>&1)"; then
  printf '%s\n' "$out"
  printf 'drift: cleanup-tmp.sh failed\n'
  exit 1
fi
printf '%s\n' "$out"

summary="$(printf '%s\n' "$out" | grep 'summary:' | tail -n 1)"
eligible="$(printf '%s\n' "$summary" | grep -o 'eligible=[0-9]*' | head -n 1 | cut -d= -f2)"
eligible_bytes="$(printf '%s\n' "$summary" | grep -o 'eligible_bytes=[^ ]*' | head -n 1 | cut -d= -f2)"
eligible="${eligible:-0}"

if [ "$eligible" -gt 0 ]; then
  printf 'drift: %s eligible leaked native libraries (%s) awaiting %s\n' \
    "$eligible" "${eligible_bytes:-unknown}" "$timer"
  drift=1
else
  printf 'ok: no eligible leaked native libraries\n'
fi

if [ "$check_timer" = 1 ] && command -v systemctl >/dev/null 2>&1; then
  active="$(systemctl --user is-active "$timer" 2>/dev/null || true)"
  enabled="$(systemctl --user is-enabled "$timer" 2>/dev/null || true)"
  if [ -z "${active}${enabled}" ]; then
    printf 'note: user manager unreachable; %s state unchecked\n' "$timer"
  elif [ "$active" = active ] && [ "$enabled" = enabled ]; then
    printf 'ok: %s active and enabled\n' "$timer"
  else
    printf 'drift: %s active=%s enabled=%s\n' "$timer" "${active:-unknown}" "${enabled:-unknown}"
    drift=1
  fi
fi

exit "$drift"
