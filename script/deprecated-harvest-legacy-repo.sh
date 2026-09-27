#!/bin/bash
# DEPRECATED: slated for absorption into the archive/ toolkit as TS
# (design wave: design/archive-migration/). Still functional; rescued 374
# unpushed commits on its 2026-09-27 dl walkthrough.
#
# Harvest a legacy-layout git checkout into an archive (jj-colocated) repo.
#
# Compfuzor's ARCHIVE_DOWNLOAD flow wants one canonical clone per upstream at
# ~/archive/<org>/<repo>, with deployment dirs carrying only a `repo` symlink.
# Deployments rendered before that layout (or created by hand) often still hold
# their own .git plus real work: branches, detached-HEAD commits, and dirty
# trees. This script moves that work into the archive as namespaced
# `harvest/<label>/...` bookmarks — without touching anything in the legacy
# checkout — so the deployment dir can later be pruned to the symlink layout
# with nothing lost.
#
# Safety posture: nothing is deleted or rewritten. Both sides get a git bundle
# beforehand, so either directory can be reconstructed even if the other is
# destroyed. Pushing to origin (optional) is the last step, never the first.
#
# Usage:
#   harvest-legacy-repo.sh LEGACY_DIR ARCHIVE_DIR [--label NAME] [--push [REMOTE]]
#
# After harvesting, verify in the archive with:
#   jj -R ARCHIVE_DIR log -r 'bookmarks()' --no-graph -T 'bookmarks ++ "\n"'
# then delete the legacy checkout only when satisfied.

set -euo pipefail

usage() { sed -n '2,20p' "$0" >&2; exit 2; }

legacy=""; archive=""; label=""; push_remote=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --label) shift; label=${1:?--label requires a value} ;;
    --push) push_remote=origin; [ "${2:-}" != "" ] && [ "${2#-}" = "${2:-}" ] && { push_remote=$2; shift; } ;;
    -h|--help) usage ;;
    -*) echo "unknown option: $1" >&2; usage ;;
    *) if [ -z "$legacy" ]; then legacy=$1; elif [ -z "$archive" ]; then archive=$1; else echo "unexpected argument: $1" >&2; usage; fi ;;
  esac
  shift
done
[ -n "$legacy" ] && [ -n "$archive" ] || usage

legacy=$(readlink -f -- "$legacy")
archive=$(readlink -f -- "$archive")
[ -d "$legacy/.git" ] || { echo "harvest: $legacy has no .git (already pruned?)" >&2; exit 1; }
[ -d "$archive/.git" ] || { echo "harvest: $archive is not a git repository" >&2; exit 1; }

label=${label:-"$(basename "$legacy")-$(date +%Y%m%d-%H%M%S)"}
stamp=$(date +%Y%m%d-%H%M%S)
bundledir=$(dirname "$archive")
count=0

echo "harvest: $legacy -> $archive as harvest/$label"

# --- safety bundles first: either side must be recoverable standalone -------
git -C "$archive" bundle create "$bundledir/$(basename "$archive").pre-harvest.$stamp.bundle" --all >/dev/null
git -C "$legacy" bundle create "$bundledir/$(basename "$legacy").harvest.$stamp.bundle" --all >/dev/null
echo "harvest: safety bundles written to $bundledir/"

# --- export jj-side commits in a colocated legacy repo so git can see them --
if [ -d "$legacy/.jj" ] && command -v jj >/dev/null 2>&1; then
  jj -R "$legacy" git export >/dev/null 2>&1 || echo "harvest: warning: jj git export failed in $legacy (jj-only commits may be missed)" >&2
fi

# --- branches ----------------------------------------------------------------
while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  git -C "$legacy" push "$archive" "+refs/heads/$branch:refs/heads/harvest/$label/$branch" >/dev/null
  echo "harvest: branch  $branch -> harvest/$label/$branch"
  count=$((count + 1))
done < <(git -C "$legacy" for-each-ref --format='%(refname:short)' refs/heads/)

# --- detached HEAD (or current head) commit if no local branch contains it --
# for-each-ref --contains is plumbing: no "(HEAD detached)" pseudo-entry.
head_sha=$(git -C "$legacy" rev-parse HEAD)
if [ -z "$(git -C "$legacy" for-each-ref --contains "$head_sha" refs/heads/)" ]; then
  git -C "$legacy" push "$archive" "+$head_sha:refs/heads/harvest/$label/head" >/dev/null
  echo "harvest: head     $head_sha -> harvest/$label/head"
  count=$((count + 1))
fi

# --- dirty working copy (tracked modifications + untracked files) ----------
tmpindex=$(mktemp)
trap 'rm -f "$tmpindex"' EXIT
rm -f "$tmpindex" # git must create it; an empty pre-existing file reads as corrupt
GIT_INDEX_FILE="$tmpindex" git -C "$legacy" add -A . >/dev/null 2>&1 || true
tree=$(GIT_INDEX_FILE="$tmpindex" git -C "$legacy" write-tree)
head_tree=$(git -C "$legacy" rev-parse 'HEAD^{tree}')
if [ "$tree" != "$head_tree" ]; then
  commit=$(git -C "$legacy" commit-tree "$tree" -p "$head_sha" -m "harvest: working copy of $legacy at $head_sha")
  git -C "$legacy" push "$archive" "+$commit:refs/heads/harvest/$label/working-copy" >/dev/null
  echo "harvest: worktree $commit -> harvest/$label/working-copy"
  count=$((count + 1))
else
  echo "harvest: worktree clean, nothing to capture"
fi

stash_count=$(git -C "$legacy" stash list | wc -l)
[ "$stash_count" -gt 0 ] && echo "harvest: note: $stash_count stash(es) exist; they are inside the safety bundle but not harvested as bookmarks"

# --- surface bookmarks in jj -------------------------------------------------
if [ -d "$archive/.jj" ] && command -v jj >/dev/null 2>&1; then
  jj -R "$archive" git import >/dev/null 2>&1 || true
  echo "harvest: jj bookmarks imported in $archive"
fi

# --- optional push upward (the disaster-proofing step) ----------------------
if [ -n "$push_remote" ]; then
  git -C "$archive" push "$push_remote" "refs/heads/harvest/*:refs/heads/harvest/*" >/dev/null
  echo "harvest: pushed harvest/* to $push_remote"
fi

echo "harvest: done ($count refs). Verify:"
echo "  jj -R '$archive' log -r 'bookmarks()' --no-graph -T 'bookmarks ++ \"\\n\"'"
echo "Prune the legacy checkout only after verifying."
