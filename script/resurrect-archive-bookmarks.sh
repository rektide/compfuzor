#!/usr/bin/env bash
# resurrect-archive-bookmarks.sh — capture pre-stomp base-bookmark positions from the jj
# op log as durable local bookmarks.
#
# Background: compfuzor renders used to `git reset --hard origin/<base>` on jj-colocated
# archive repos (~/archive/<org>/<repo>). Each reset made jj's auto-import move the base
# bookmark (main/master) and reparent the working copy. The op log still records the old
# bookmark positions, but op-log retention is finite — this script turns them into local
# bookmarks, which colocated repos export to git refs (that's the durability).
#
# What counts as "lost": a commit the base bookmark pointed to at some older operation that
# is NOT an ancestor of the current base-bookmark tip (checked via revsets, not SHA string
# comparison). Positions still reachable from the current tip are not lost and are skipped.
#
# Per lost position (deduped by commit id, ordered most-recent-first):
#   - name: <base>-resurrect-<YYYYMMDD-HHMM>, datestamp from the timestamp of the last
#     operation at which that position was still current ("last seen", ~= stomp moment).
#   - the most recent lost position gets the plain name; older distinct positions get their
#     own datestamps (usually distinct). On a name collision (same-minute stomps, or an
#     already-existing bookmark) a -2, -3, ... suffix is appended in recency order until
#     the name is free — existing bookmarks are NEVER moved or duplicated.
#   - if any existing bookmark already points at the position, it is reported as
#     "already captured" and skipped (idempotence).
#
# Repos are read via `jj --at-op=<id> bookmark list`, so no `op restore`, no resets, no
# working-copy writes. The only mutation (under --apply) is `jj bookmark create`.
# Local bookmarks only: this script NEVER pushes to any remote.
#
# Usage:
#   script/resurrect-archive-bookmarks.sh [options] [<repo>...]
#
# Options:
#   -r, --apply          Create the bookmarks (default: dry-run, no changes).
#   -n, --max-ops N      Only inspect the newest N operations per repo (default: all).
#   -h, --help           Show this help.
#
# With no <repo> arguments, auto-discovers jj-colocated archive repos via /opt/*/repo
# symlinks that resolve under $HOME/archive/.
#
# Exit status: 0 on success (repos with nothing to do are fine), 1 on errors.
#
# jj invocations relied on (verified on jj 0.45.1):
#   jj -R <repo> --ignore-working-copy op log --no-graph -T '<op id/ts>'
#   jj -R <repo> --at-op=<op> bookmark list <base> -T 'if(normal_target, ...)'
#   jj -R <repo> --ignore-working-copy log -r '<pos> & ::<tip>'   (ancestor check)
#   jj -R <repo> --ignore-working-copy bookmark create -r <pos> <name>

set -euo pipefail

APPLY=false
MAX_OPS=()
repos=()

usage() {
  cat <<'EOF'
resurrect-archive-bookmarks.sh — capture pre-stomp base-bookmark positions from the jj
op log as durable local bookmarks.

Usage:
  script/resurrect-archive-bookmarks.sh [options] [<repo>...]

Options:
  -r, --apply          Create the bookmarks (default: dry-run, no changes).
  -n, --max-ops N      Only inspect the newest N operations per repo (default: all).
  -h, --help           Show this help.

With no <repo> arguments, auto-discovers jj-colocated archive repos via /opt/*/repo
symlinks that resolve under $HOME/archive/.

Details:
  "Lost" = a commit the base bookmark (main/master/…) pointed to at some older operation
  that is not an ancestor of the current base-bookmark tip (revset check, not SHA compare).
  Each lost position becomes <base>-resurrect-<YYYYMMDD-HHMM>, datestamped by the last op
  at which it was still current. Name collisions get -2, -3 suffixes; existing bookmarks
  are never moved. Dry-run by default; under --apply the only mutation is jj bookmark
  create (local bookmarks only — never pushes).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    -r|--apply) APPLY=true ;;
    -n|--max-ops) shift; [ $# -gt 0 ] || { echo "error: --max-ops needs a value" >&2; exit 2; }; MAX_OPS=(-n "$1") ;;
    --max-ops=*) MAX_OPS=(-n "${1#--max-ops=}") ;;
    -h|--help) usage; exit 0 ;;
    --) shift; repos+=("$@"); break ;;
    -*) echo "error: unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) repos+=("$1") ;;
  esac
  shift
done

# Discover jj-colocated archive repos from /opt/*/repo symlinks when none were given.
if [ ${#repos[@]} -eq 0 ]; then
  for link in /opt/*/repo; do
    [ -e "$link" ] || continue
    resolved=$(readlink -f "$link" 2>/dev/null) || continue
    case "$resolved" in
      "$HOME"/archive/*) [ -d "$resolved/.jj" ] && repos+=("$resolved") ;;
    esac
  done
  # Dedupe (multiple /opt entries can point at the same archive), keep sorted order.
  mapfile -t repos < <(printf '%s\n' "${repos[@]}" | LC_ALL=C sort -u)
fi
[ ${#repos[@]} -gt 0 ] || { echo "no jj-colocated archive repos found" >&2; exit 1; }

MODE="DRY-RUN (no changes)"
$APPLY && MODE="APPLY (will create bookmarks)"

errors=0
total_created=0

note() { printf '  %s\n' "$*"; }
warn() { printf '  warning: %s\n' "$*" >&2; }

# base bookmark for a repo: prefer conventional names, else the sole local bookmark.
# Prints the name to stdout; diagnostics go to stderr (stdout is captured by the caller).
find_base() {
  local repo=$1 names=() name
  mapfile -t names < <(jj -R "$repo" --ignore-working-copy bookmark list -T 'name ++ "\n"' 2>/dev/null) || true
  [ ${#names[@]} -gt 0 ] || { warn "no local bookmarks, skipping"; return 1; }
  for name in main master trunk develop default; do
    if printf '%s\n' "${names[@]}" | grep -qx "$name"; then
      printf '%s' "$name"
      return 0
    fi
  done
  if [ ${#names[@]} -eq 1 ]; then
    printf '%s' "${names[0]}"
    return 0
  fi
  warn "ambiguous base bookmark (locals: ${names[*]}), skipping"
  return 1
}

# full commit id a local bookmark points to (empty if absent, "CONFLICT" if conflicted)
bookmark_target() {
  jj -R "$1" --ignore-working-copy bookmark list "$2" \
    -T 'if(normal_target, normal_target.commit_id(), "CONFLICT")' 2>/dev/null || true
}

# is $2 an ancestor of (or equal to) $3?  0=yes 1=no 2=cannot tell.
# Prefers the jj revset reachability check; falls back to git when the tip isn't
# imported into jj yet (jj auto-import is suppressed by --ignore-working-copy).
is_ancestor() {
  local out
  if out=$(jj -R "$1" --ignore-working-copy log --no-graph \
               -r "$2 & ::$3" -T commit_id 2>/dev/null); then
    [ -n "$out" ] && return 0 || return 1
  fi
  local rc=0
  git -C "$1" merge-base --is-ancestor "$2" "$3" 2>/dev/null || rc=$?
  [ "$rc" -le 1 ] && return "$rc" || return 2
}

process_repo() {
  local repo=$1
  printf '%s\n' "== $repo"

  local base
  base=$(find_base "$repo") || return 0

  local current
  # In colocated repos the git ref is the durable truth and can be ahead of jj's
  # view (git resets aren't imported until a jj command without --ignore-working-copy).
  current=$(git -C "$repo" rev-parse --verify -q "refs/heads/$base") || current=
  [ -n "$current" ] || current=$(bookmark_target "$repo" "$base")   # non-colocated fallback
  if [ -z "$current" ]; then
    note "base bookmark '$base' has no local target now; every historical position counts as lost"
  elif [ "$current" = "CONFLICT" ]; then
    note "base bookmark '$base' is conflicted; resolving conflicts is out of scope, skipping"
    return 0
  fi

  # Walk the op log oldest->newest. -n (if set) keeps the newest N ops, tac restores
  # chronological order so "last seen" per position is the latest op holding it.
  local -a ops=()
  mapfile -t ops < <(jj -R "$repo" --ignore-working-copy op log --no-graph "${MAX_OPS[@]}" \
      -T 'self.id().short() ++ "\t" ++ self.time().start().local().format("%s") ++
          "\t" ++ self.time().start().local().format("%Y%m%d-%H%M") ++ "\n"' \
      2>/dev/null | tac) || true
  [ ${#ops[@]} -gt 0 ] || { note "no operations in op log, skipping"; return 0; }

  # position (full commit id) -> "epoch|datestamp|opid" of last op where it was current
  local -A seen=()
  local op epoch stamp opid pos
  for op in "${ops[@]}"; do
    IFS=$'\t' read -r opid epoch stamp <<<"$op"
    [ -n "$opid" ] || continue
    pos=$(jj -R "$repo" --at-op="$opid" bookmark list "$base" \
          -T 'if(normal_target, normal_target.commit_id(), "")' 2>/dev/null) || true
    [ -n "$pos" ] || continue   # bookmark absent or conflicted at this op
    # keep the latest op per position (ops are chronological; compare epochs anyway)
    if [ -z "${seen[$pos]:-}" ] || [ "${seen[$pos]%%|*}" -lt "$epoch" ]; then
      seen[$pos]="$epoch|$stamp|$opid"
    fi
  done
  [ ${#seen[@]} -gt 0 ] || { note "no recorded positions for '$base' in op log"; return 0; }

  # Collect lost positions: != current tip and not reachable from it.
  local -a lost=()   # "epoch|stamp|opid|pos"
  for pos in "${!seen[@]}"; do
    [ -n "$current" ] || { lost+=("${seen[$pos]}|$pos"); continue; }   # no current tip: nothing can contain it
    [ "$pos" != "$current" ] || continue                               # still the tip, not lost
    local rc=0
    is_ancestor "$repo" "$pos" "$current" || rc=$?
    case $rc in
      0) continue ;;   # still reachable from the current tip, not lost
      2) warn "cannot resolve position $pos vs tip $current, skipping it"; continue ;;
    esac
    lost+=("${seen[$pos]}|$pos")
  done
  [ ${#lost[@]} -gt 0 ] || { note "no lost '$base' positions (all recorded tips reachable from current)"; return 0; }

  # Most recent first.
  mapfile -t lost < <(printf '%s\n' "${lost[@]}" | LC_ALL=C sort -t'|' -k1,1nr)

  local count=0 entry
  for entry in "${lost[@]}"; do
    IFS='|' read -r epoch stamp opid pos <<<"$entry"
    local name="${base}-resurrect-${stamp}" n=2 existing
    local cand="$name"
    # Skip if some existing bookmark already captures this position (idempotence).
    # Captures = git branch refs (always fresh in colocated repos; the resurrect
    # bookmarks we create are exported there) + jj bookmarks other than the base
    # itself (the base bookmark is the thing that got stomped — its jj target may
    # be stale next to the git ref, and by definition it doesn't "capture" its
    # former positions). Compared in bash; CommitId == String isn't valid template syntax.
    local captures
    captures=$(git -C "$repo" for-each-ref refs/heads \
               --format='%(objectname) %(refname:short)' 2>/dev/null || true)
    captures+=$'\n'"$(jj -R "$repo" --ignore-working-copy bookmark list \
               -T 'if(normal_target, normal_target.commit_id() ++ " " ++ name ++ "\n")' 2>/dev/null \
               | grep -v " $base\$" || true)"
    existing=$(printf '%s\n' "$captures" | grep "^$pos " | cut -d' ' -f2- | sort -u | tr '\n' ' ')
    if [ -n "$existing" ]; then
      note "already captured: $pos (last seen $stamp, op $opid) -> $existing"
      continue
    fi
    # Else find a free name; existing bookmarks are never moved or duplicated.
    # Check git branch names too: a git-only branch (not yet imported by jj) would
    # collide at export time when `jj bookmark create` runs.
    while git -C "$repo" show-ref --verify -q "refs/heads/$cand" 2>/dev/null ||
          [ -n "$(bookmark_target "$repo" "$cand")" ]; do
      cand="${name}-${n}"; n=$((n + 1))
    done
    if $APPLY; then
      jj -R "$repo" --ignore-working-copy bookmark create -r "$pos" "$cand" >/dev/null
      note "created $cand -> $pos (last seen $stamp, op $opid)"
      total_created=$((total_created + 1))
    else
      note "would create $cand -> $pos (last seen $stamp, op $opid)"
      total_created=$((total_created + 1))
    fi
    count=$((count + 1))
  done
  if [ "$count" -eq 0 ]; then
    note "nothing to do (all lost positions already captured)"
  fi
}

printf 'resurrect-archive-bookmarks — capturing pre-stomp bookmark positions\n'
printf 'mode: %s — repos: %d\n\n' "$MODE" "${#repos[@]}"

for repo in "${repos[@]}"; do
  resolved=$(readlink -f "$repo" 2>/dev/null) || resolved=$repo
  if ! [ -d "$resolved/.jj" ]; then
    printf '%s\n' "== $repo"
    note "not a jj repo, skipping"
    errors=$((errors + 1))
    continue
  fi
  process_repo "$resolved" || errors=$((errors + 1))
  echo
done

printf 'summary: %d bookmark(s) %s across %d repo(s)\n' \
  "$total_created" "$([ "$APPLY" = true ] && echo created || echo 'would be created')" "${#repos[@]}"
[ "$errors" -eq 0 ] || printf 'warning: %d repo(s) had errors\n' "$errors" >&2
exit $([ "$errors" -eq 0 ] && echo 0 || echo 1)
