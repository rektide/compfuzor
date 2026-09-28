---
type: Design
title: Dirty standalone Git checkouts at the archive-workspace boundary
description: Fixture-tested jj 0.45.1 conversion mechanics and the exact limit where a dirty Git index ceases to be preserved by a jj worktree snapshot.
resource: /design/archive-workspace/dirty-conversion0.gpt6sol.md
tags: [compfuzor, archive, jj, git, workspace, dirty-checkout]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-28 }
verified: { by: model:gpt6sol, at: 2026-09-28 }
stale_after: 2026-12-28
sources:
  - id: dirty-fixture
    resource: /.test-agent/dirty-workspace-study/probe.sh
    title: Disposable local dirty checkout probe; run2/observations.txt contains command output
  - id: prior-workspace-study
    resource: /design/archive-workspace/conversion1.gpt6luna.md
    title: Clean no-copy conversion and path-invariant study
  - id: jj-source
    resource: https://github.com/jj-vcs/jj/tree/803ef00a0a6ee4ddc275d3138d5f9e7326399906
    title: Local Jujutsu source checkout at 803ef00 (version 0.45.1)
---

# Dirty standalone Git checkouts at the archive-workspace boundary

## Question and answer

Can a **standalone Git checkout** with a local branch, modified tracked files,
untracked files, and ignored runtime state become a jj workspace at its *same
path*, backed by the canonical `~/archive/<org>/<repo>`? **Structurally yes, in
the tested narrow case**: absent archive, one filesystem, no existing linked
workspaces/worktrees, a quiesced checkout, and a supported jj/Git layout. The
original ordinary files (including ignored files) can retain their inodes at
the source path. The local branch and history survive in the shared Git repo.
The new source workspace has a different `@`; the archive root remains a
separate workspace.

**Not lossless for dirty Git state by default.** `jj git init --colocate`
snapshots the working *tree*, and a bookmark can pin it, but that one tree does
not encode the prior staged/unstaged split. An index-only version was lost from
*both live indexes* in the fixture even though its blob was still in the Git
object database. Therefore a source containing staged content cannot be
promised an unchanged, restorable Git staging state by this sequence. Full
original repository metadata also is not preserved unchanged: `.git` is moved
to the archive and operated on by jj/Git. For the requested default **dirty =
fail**, stop before any jj mutation; an explicit **save** mode requires a
declared, narrower preservation contract, especially for index-only content.

This study concerns the initial *same-repository* conversion. It does not
implement the later fetch/bookmark/advance pipeline or authorize a real
checkout migration. It follows the [operator's current update direction](/design/archive-workspace/direction0.gpt6astra.md)
and investigates the source-preservation gap left by the [clean conversion
study](/design/archive-workspace/conversion1.gpt6luna.md).

## Version, source, and reproduction

Installed jj: `0.45.1-33d3a595429b7e3b54a8ea769560247913bc8a1b`;
local first-party source at `~/archive/jj-vcs/jj` was read at commit
`803ef00a0a6ee4ddc275d3138d5f9e7326399906` (same release, different
build commit). Git: 2.55.0 as recorded by [conversion1](/design/archive-workspace/conversion1.gpt6luna.md#tested-scope-and-evidence).
The actual CLI output is in the ignored scratch
[`run2/observations.txt`](/.test-agent/dirty-workspace-study/run2/observations.txt);
the reproducible fixture is
[`probe.sh`](/.test-agent/dirty-workspace-study/probe.sh) and its
[`README.md`](/.test-agent/dirty-workspace-study/README.md). Run it *only* in
scratch from the Compfuzor root:

```sh
CASE_NAME=run3 .test-agent/dirty-workspace-study/probe.sh
```

It refuses to overwrite `run3` if that path exists. The fixture constructs
`main` and a checked-out `private-branch` with a local-only commit, then:

| Before jj | Fixture observation |
|---|---|
| `tracked.txt` | Different staged and unstaged content (`MM`) |
| `index-only.txt` | Staged blob `2aaa280e…` but worktree restored to HEAD (`MM`) |
| `new.txt` | Untracked (`??`) |
| `.runtime/db` | Git-ignored (`!!`), bytes `live-db` |

The following is a **self-contained disposable reproduction** from the
Compfuzor root; choose an absent case directory. It exercises the same jj
commands and root/metadata exchanges as `probe.sh`. Never substitute a live
checkout or real archive for these fixture paths:

```bash
set -euo pipefail
base="$PWD/.test-agent/dirty-workspace-study/manual-case"
test ! -e "$base" || { echo 'Fixture already exists' >&2; exit 1; }
source="$base/legacy"
archive="$base/archive/example/project"
mkdir -p "$source" "$(dirname "$archive")"
export GIT_AUTHOR_NAME=Fixture GIT_COMMITTER_NAME=Fixture
export GIT_AUTHOR_EMAIL=fixture@example.invalid GIT_COMMITTER_EMAIL=fixture@example.invalid
git -C "$source" init --initial-branch=main
printf '.runtime/\n' >"$source/.gitignore"
printf 'base\n' >"$source/tracked.txt"
printf 'old\n' >"$source/index-only.txt"
git -C "$source" add .gitignore tracked.txt index-only.txt
git -C "$source" commit -m baseline
git -C "$source" switch -c private-branch
printf 'local branch commit\n' >"$source/branch.txt"
git -C "$source" add branch.txt
git -C "$source" commit -m 'local only'
printf 'staged\n' >"$source/tracked.txt"
git -C "$source" add tracked.txt
printf 'unstaged beyond staged\n' >"$source/tracked.txt"
printf 'staged-only value\n' >"$source/index-only.txt"
git -C "$source" add index-only.txt
printf 'old\n' >"$source/index-only.txt"  # staged version exists only in index
printf 'untracked\n' >"$source/new.txt"
mkdir -p "$source/.runtime"
printf 'live-db\n' >"$source/.runtime/db"
source_inode="$(stat -c '%d:%i' "$source")"
db_inode="$(stat -c '%d:%i' "$source/.runtime/db")"
branch_oid="$(git -C "$source" rev-parse refs/heads/private-branch)"
stage_oid="$(git -C "$source" rev-parse :index-only.txt)"
git -C "$source" status --short --ignored  # probe only in this fixture

mv -T -- "$source" "$archive"  # absent archive, same filesystem
(
  cd "$archive"
  jj --config user.name=Fixture --config user.email=fixture@example.invalid git init --colocate
  jj --config user.name=Fixture --config user.email=fixture@example.invalid status
  test "$(git rev-parse :index-only.txt)" = "$stage_oid"
  jj --config user.name=Fixture --config user.email=fixture@example.invalid bookmark create rescued-dirty --revision @
  test "$(git rev-parse :index-only.txt)" != "$stage_oid"  # staging collapsed
  jj --config user.name=Fixture --config user.email=fixture@example.invalid workspace add --colocate --name deployment --revision @ "$source"
)
# Do not run VCS/application commands between these first and last renames.
mv -T -- "$archive" "$base/root-hold"
mv -T -- "$source" "$archive"
mv -T -- "$base/root-hold" "$source"
mkdir "$base/metadata-hold"
mv -T -- "$source/.git" "$base/metadata-hold/main-git"
mv -T -- "$source/.jj" "$base/metadata-hold/main-jj"
mv -T -- "$archive/.git" "$source/.git"
mv -T -- "$archive/.jj" "$source/.jj"
mv -T -- "$base/metadata-hold/main-git" "$archive/.git"
mv -T -- "$base/metadata-hold/main-jj" "$archive/.jj"
rmdir "$base/metadata-hold"

test "$(stat -c '%d:%i' "$source")" = "$source_inode"
test "$(stat -c '%d:%i' "$source/.runtime/db")" = "$db_inode"
test "$(git -C "$archive" rev-parse refs/heads/private-branch)" = "$branch_oid"
git -C "$archive" cat-file -e "$stage_oid"  # present != pinned
test "$(git -C "$source" rev-parse :index-only.txt)" != "$stage_oid"
(cd "$source" && jj workspace list && jj status)
```

The no-copy swap uses **nine directory-entry renames** (three for the roots,
six for `.git`/`.jj`), not a jj command or an atomic transaction. No VCS/application access is safe
between the first and last rename. The tested version's `workspace add`
[rejects an occupied destination](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/cli/src/commands/workspace/add.rs#L132-L145);
its `--colocate` path first creates a Git linked worktree and then a jj
workspace ([source lines 147–176](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/cli/src/commands/workspace/add.rs#L147-L176)).
`--revision @` is important: the new workspace is based on the snapshotted
dirty revision, whereas omission bases it on the current `@`'s parents (see
`jj workspace add --help`). After the swap, the original ordinary data and
directory inode are again at `$source`; the archive owns the original `.git`
common dir/`.jj` store and a generated worktree. The generated `.git` and
`.jj` pointers return to `$source`, so there is no hand-written jj store edit.

## Exact dirty-state observations

1. `jj git init --colocate` imported `main` and `private-branch` with their
   original OIDs; `@-` was the private-branch commit. It snapshot `new.txt`
   and the final worktree version of `tracked.txt` into `@`. The ignored
   `.runtime/db` did not enter that revision. Initialization's existing-Git
   branch and snapshot flow is at [upstream `git/init.rs` lines
   197–257](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/cli/src/commands/git/init.rs#L197-L257).
2. In this particular run, immediately after init and `jj status`, the original
   staged-only blob was *still* at `:index-only.txt`. **The next `jj bookmark
   create rescued-dirty --revision @` replaced that index entry with the
   worktree/HEAD blob** (`3367afdb…`); `workspace add` created its *own* index
   with the same latter blob. The original index SHA-256 differed afterward.
   The first jj command to erase staging can depend on command sequence;
   neither `git init`'s temporary retention here nor a clean `jj status`
   guarantees staged state is durable.
3. After the root/metadata exchange the original directory and ignored DB
   retained their device/inodes at the source. The archive did *not* acquire
   `.runtime/`. `jj workspace list` and `jj workspace root --name deployment`
   resolved correctly, and source `jj status` reported clean against a new
   empty `@` whose parent was the rescued dirty bookmark. Original
   `private-branch` still pointed at its local-only commit; the rescue bookmark
   pointed at the **worktree** snapshot. Git at the new source worktree had a
   detached HEAD, rather than the original checked-out branch relationship.
4. The original staged-only blob remained readable with `git cat-file -e`
   because it was an object already written by `git add`. No tested branch,
   bookmark, or jj snapshot referenced that version. Its mere presence now
   is **not durable custody** and does not reconstruct the staged state. Both
   Git worktree indexes at the end contained the worktree/HEAD blob.

Source evidence: [`run2/observations.txt` lines 12–19,
23–54, 56–88](/.test-agent/dirty-workspace-study/run2/observations.txt).
The earlier [dirty snapshot fixture](/.test-agent/archive-workspace-conversion/dirty-snapshot-fixture.sh)
likewise observes staged+unstaged collapse, but does not isolate an index-only
version. The [upstream Git compatibility guide](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/docs/git-compatibility.md#L44-L50)
explicitly says the staging area is ignored and
[warns about non-understood Git states](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/docs/git-compatibility.md#L148-L160).

## What “safe” can mean here

| Property | In this fixture | Unproven / tradeoff |
|---|---|---|
| Tracked/untracked final worktree bytes | Snapshotted in jj `@` and present at original source path after swap | Snapshot ignores ignored paths; jj config/file limits and unusual Git states need admission. |
| Ignored/runtime data | Original inodes and bytes remained at source after swap | No atomicity or live-process guarantee; files must be quiesced. Not recorded by jj/bookmark. |
| Local branch/history | `private-branch` kept its original OID in archive `.git` and jj bookmarks | Branch no longer checked out at source; archive-root Git may still identify it as checked out. No push or upstream availability claim. |
| Dirty *worktree* revision | Explicit rescue bookmark points to it | A jj snapshot is one tree, not Git's staged/unstaged versions or a commitment to publish it. |
| Original Git repository metadata | `.git` moved with its refs, reflogs, objects and configuration to archive; selected objects/refs verified in earlier clean fixture | Metadata is subsequently mutated. Index changed in this dirty fixture; reflogs, all unreachable objects and repo-specific extensions were not comprehensively proved unchanged. |
| Stage-only content | Blob still existed as an unreferenced object after test | Neither live index retained the stage; object GC/expiry can remove it. Do not advertise this as preservation. |

For the **default dirty-fail** policy, admission must detect tracked worktree
changes, nonignored untracked paths, staged-only or split changes, in-progress
operations, and unknown state *before* moving or initializing the checkout.
`jj --ignore-working-copy status` deliberately does not inspect unsnapshotted
files, whereas ordinary `jj status` can snapshot them; see the
[earlier probe](/design/archive-workspace/conversion0.gpt6luna.md#dirty-state-and-the-admission-gate).
Do not call unguarded `git status` read-only: it can refresh/write the index
and run configured helpers. The [local helper/optional-lock probe](/archive/src/custody/inventory/probe.ts)
and [safety review](/design/archive-toolkit/safety-review0.gpt6sol.md)
provide relevant evidence; using them for this new admission path still needs
an explicit design and test. A pinned `health` result does not certify a clean
working tree ([toolkit README](/archive/README.md#maintain-a-checkout)).

For an **opt-in save** policy, the minimally tested interpretation is “preserve
the final tracked/untracked worktree as a jj revision with a named bookmark,
and retain ignored files physically at the source.” It must explicitly warn
that Git staging state is discarded. If the requested contract instead
includes staged-only versions, **the fixture recipe is inadequate without an
additional pre-jj custody step**. Plausible choices to investigate: preserve
an exact original index/metadata snapshot separately before the first jj
command; or construct and pin a Git commit/tree of the pre-init staged index
*as well as* the worktree snapshot, then verify reconstruction of both states.
Neither was validated by this study. Avoid promising complete Git state based
solely on copying an index: restoring it requires the matching Git HEAD,
objects, index extensions, and per-worktree context.

For a user who insists on **not mutating original repository metadata at all**,
retain the original checkout untouched as a recovery artifact and create the
archive from a separate verified copy; any subsequent use of the original path
still requires an explicit cutover and a policy for that retained copy. That is
an alternative with cost, **not** an agreed requirement. For a clean-input
route, arrange that dirty state is deliberately resolved in Git before trying
the [existing clean conversion sequence](/design/archive-workspace/conversion1.gpt6luna.md#the-no-copy-operation).

An already-existing independent archive cannot absorb the occupied original
checkout via `jj workspace add`: it only creates a workspace in its *current*
repository, and rejects a nonempty target. First establish whose repository
will own refs/objects and how conflicting refs, old indexes and ignored state
are handled. External Git worktrees or jj workspaces require path repair or
deferral; moving a shared root breaks their relative links and jj's workspace
store, which `git worktree repair` alone does not fix
([prior fixture](/design/archive-workspace/conversion0.gpt6luna.md#existing-external-workspaces-are-a-migration-blocker)).
Cross-filesystem moves, partial/shallow/LFS/submodule/linked-gitdir variants,
crash interruption, and live writers are outside this proof. There is no
supported single jj command that performs the whole transition atomically.

## Architectural checkpoint

**Possible:** use the existing *whole* Git repository as the canonical
archive, let jj create a genuine colocated linked workspace, exchange the
ordinary trees and restore generated metadata pointers, retain source runtime
inodes, and pin a dirty worktree revision while keeping a local branch. Regular
updates can subsequently select only the deployment workspace; clean-case
fixtures show its `@` can change without changing archive-main `@`.

**Impossible under the tested commands:** attach jj in-place over the populated
source; represent two distinct Git index/worktree versions in one jj snapshot;
guarantee unchanged original Git metadata or atomic live-service cutover.
Branch existence is separate from whether its tip is available upstream.

**Unresolved tensions:** whether “save dirty” explicitly permits stage collapse
or demands separate index custody; whether a retained untouched original repo
is desired; preflight behavior in the presence of executable helpers, sparse
state, and external workspaces; what to do if the canonical archive already
exists; and how to journal/recover a partial exchange. None should be
decided implicitly by the existing `refresh` command, which currently only
[operates on a selected destination](/tasks/compfuzor/repo_jj_archive.tasks#L59-L76).

**Proposed next slice:** agree the exact dirty-save contract first, then test
one *guarded* source admission + staged-only preservation option in a new
disposable fixture (including restoration proof and an intentionally interrupted
rename checkpoint). Keep the default refusal and the regular
dirty → upstream availability → bookmark → advance pipeline in view; do not
advance a deployment workspace before any required preservation succeeds.

## Cross-references

- [Archive-workspace direction](/design/archive-workspace/direction0.gpt6astra.md)
  — current desired conversion/update policy, including the dirty-fail default.
- [Clean no-copy conversion](/design/archive-workspace/conversion1.gpt6luna.md)
  — source-path inode, metadata pointer, and interruption boundaries on which
  this dirty fixture builds.
- [First conversion study](/design/archive-workspace/conversion0.gpt6luna.md)
  — workspace creation constraints and external-workspace failure evidence.
- [Archive toolkit safety review](/design/archive-toolkit/safety-review0.gpt6sol.md)
  — why status/helper preflight cannot be assumed read-only.
- [Existing archive toolkit README](/archive/README.md#compfuzor-integration)
  — describes the *current* refresh integration, not the requested structural
  conversion or update-policy pipeline.
