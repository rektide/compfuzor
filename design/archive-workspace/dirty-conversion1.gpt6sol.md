---
type: Design
title: Preserve staged B and worktree C during archive-backed workspace conversion
description: Tested copy-first staged-index commit, jj worktree snapshot, and source-path cutover without moving the original Git branch.
resource: /design/archive-workspace/dirty-conversion1.gpt6sol.md
tags: [compfuzor, archive, jj, git, workspace, staged-index, migration]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-28 }
verified: { by: model:gpt6sol, at: 2026-09-28 }
stale_after: 2026-12-28
sources:
  - id: prior-dirty-study
    resource: /design/archive-workspace/dirty-conversion0.gpt6sol.md
    title: Earlier fixture exposing staged-only loss in an unprotected jj snapshot
  - id: copy-first-fixture
    resource: /.test-agent/dirty-workspace-study/staged-commit-copy-first.sh
    title: Disposable staged B plus worktree C conversion probe
  - id: ordinary-commit-fixture
    resource: /.test-agent/dirty-workspace-study/plain-git-commit.sh
    title: Disposable proof that git commit advances the checked-out branch
---

# Preserve staged B and worktree C during archive-backed workspace conversion

## Result and change in policy

The operator **accepts creating a commit for index-only staged content**.
Under that policy the [earlier result](/design/archive-workspace/dirty-conversion0.gpt6sol.md)
is not a reason to reject a dirty checkout. A new fixture proves a practical
sequence for a *plain standalone Git checkout*, with its canonical archive
path absent, no external Git worktrees/jj workspaces, and both paths on one
filesystem:

1. Copy the whole, quiesced original checkout into an archive candidate **before
   modifying the original**. In that copy, write the *pre-jj Git index* as
   commit **B**, parented to the checked-out local branch tip **A**, and put B
   under a separate, collision-checked ref. Do not advance the local branch.
2. `jj git init --colocate` in the archive copy snapshots the final ordinary
   working tree **C** (including nonignored untracked files); bookmark C. B and
   C are **siblings from A**, not a linear B→C chain. The content difference
   B→C still describes the unstaged/reverted portions plus formerly untracked
   content. Git refs make both revisions durable within this repository.
3. Verify B, C, original branch OIDs, and the still-untouched source. Only then
   move the source aside, `jj workspace add --colocate --revision
   preserve-worktree-C` at its old path, return the original ordinary root
   there, and replace only its `.git` with the generated linked-worktree
   pointer. The generated `.jj` metadata also goes to the original path.
   Retain the original `.git` separately rather than deleting it.

The source path ends as a real jj+Git linked workspace of the archive repo,
with its original root/ordinary file inodes and ignored runtime bytes still
there. The archive root is another workspace; updating the source workspace
does not require moving the archive root's `@` (as already verified for the
[clean conversion topology](/design/archive-workspace/conversion1.gpt6luna.md#result)).
This is a **fixture result, not a proven production transaction**. No source
files, Git index, refs, or reflogs were intentionally written *up to the
cutover gate* (filesystem access times were not audited). Its repository
identity necessarily changes when the linked `.git`/`.jj` entries are
installed at the old path.

## Does the pre-jj commit move the local branch?

An ordinary `git commit -m 'save staged B'` **does** advance whichever branch
is checked out. In a disposable [plain-Git fixture](/.test-agent/dirty-workspace-study/plain-git-commit/observations.txt#L6-L15),
`private-branch` changed from `574098e…` to `ca3b562…` (its original tip became
the new commit's parent); worktree C remained on disk but was now unstaged
against B. That is a valid alternative **only if branch movement is intended**.

The tested non-moving route operates in the **archive copy** and uses Git's
index-to-tree/commit plumbing:

```bash
base_oid="$(git -C "$archive" rev-parse refs/heads/private-branch)"
b_tree="$(git -C "$archive" write-tree)"
b_commit="$(printf 'Preserve original staged Git index B\n' |
  git -C "$archive" commit-tree "$b_tree" -p "$base_oid")"
git -C "$archive" update-ref refs/heads/preserve-index-B "$b_commit" ''
```

The final empty argument to `git update-ref` means “expect this ref to be
absent”; an existing name fails instead of being overwritten. Git creates B
as a *new commit object* plus a new ref. No `git commit` or branch-switch runs
on `private-branch`; `main` and `private-branch` retained their exact original
OIDs before and after jj initialization and workspace creation. Doing the same
plumbing directly in the source would also leave its branch OID intact, **but
would write objects and a ref into the source before cutover**. Copy-first
avoids that early source mutation. `commit-tree` needs a Git author/committer
identity; the fixture supplies it via environment variables.

## Reproducible commands and measurements

Run only the disposable fixtures; names are guarded and no real checkout or
archive is touched:

```sh
CASE_NAME=copy-first-new .test-agent/dirty-workspace-study/staged-commit-copy-first.sh
# Independent comparison of ordinary git commit vs. detached commit-tree:
CASE_NAME=plain-git-commit-new .test-agent/dirty-workspace-study/plain-git-commit.sh
```

Both scripts refuse to overwrite a case; choose a different `CASE_NAME` on
repeat. The original plain-Git run's
[observations](/.test-agent/dirty-workspace-study/plain-git-commit/observations.txt)
are retained. The full [copy-first fixture](/.test-agent/dirty-workspace-study/staged-commit-copy-first.sh)
constructs a local-only branch, a tracked file with B staged/C on disk, an
index-only B version reverted to A on disk, a C-only untracked file, and an
ignored `.runtime/db`. It records source branch OIDs, index hash, branch
reflog hash, and root/DB inodes before copy. In contrast to the earlier dirty
fixture, it does **not** run `git status` on the original source; a status
observation on the archive copy occurs *after B is pinned*.

The essential commands after constructing that fixture (all paths must be
unique, absent, and inside scratch) are:

```bash
# source = original populated checkout; archive = absent path on same device;
# hold, generated_hold, old_git = distinct absent hold paths on same device.
mkdir -p "$(dirname -- "$archive")"
cp -a -- "$source" "$archive"
# Assert archive/.git/index bytes match source/.git/index BEFORE any Git status.
branch_oid="$(git -C "$archive" rev-parse refs/heads/private-branch)"
b_tree="$(git -C "$archive" write-tree)"
b_commit="$(printf 'Preserve original staged Git index B\n' |
  git -C "$archive" commit-tree "$b_tree" -p "$branch_oid")"
git -C "$archive" update-ref refs/heads/preserve-index-B "$b_commit" ''
(
  cd "$archive"
  jj --config user.name=Fixture --config user.email=fixture@example.invalid git init --colocate
  jj --config user.name=Fixture --config user.email=fixture@example.invalid bookmark create preserve-worktree-C --revision @
)
# GATE: verify exact B tree and parent; C tree, parent, and bookmark;
# unchanged private/main branch OIDs; source index/ref/reflog hashes,
# ordinary bytes and ignored runtime before moving anything at source.

mv -T -- "$source" "$hold"
(
  cd "$archive"
  jj --config user.name=Fixture --config user.email=fixture@example.invalid workspace add \
    --colocate --name deployment --revision preserve-worktree-C "$source"
)
# Source has new linked Git + jj workspace; hold has original intact checkout.
# Exchange directory roots, then move Git/jj metadata to the intended roots.
# NO Git, jj, application or status command between the first and last moves.
mv -T -- "$source" "$generated_hold"
mv -T -- "$hold" "$source"
mv -T -- "$generated_hold" "$hold"
mv -T -- "$source/.git" "$old_git"  # retain original Git dir intact
mv -T -- "$hold/.git" "$source/.git"
mv -T -- "$hold/.jj" "$source/.jj"
```

`$source` originally has no `.jj`; the generated workspace supplies it.
Unlike the prior move-first [root/metadata exchange](/design/archive-workspace/conversion1.gpt6luna.md#the-no-copy-operation),
the original `.git` is not the archive's repository—it was *copied* there
first—so it is retained at `$old_git`, not transplanted into the archive.
Neither the original `.git` nor the generated hold root is deleted by this
sequence. On interruption, the held roots/entries must be identified from
their actual paths before resuming; **the shell fragment is a reproduction,
not an idempotent migration script**.

Observed jj 0.45.1 / Git 2.55.0 outcome in the latest
[`staged-commit-copy-first4/observations.txt`](/.test-agent/dirty-workspace-study/staged-commit-copy-first4/observations.txt):

| Check | Observation |
|---|---|
| Starting `private-branch`, `main` | `408f5ac…`, `b707ccc…`; each exact OID is unchanged after conversion. |
| B: `git show preserve-index-B:index-only.txt` | `B index only`; `git show preserve-index-B:tracked.txt` = `B staged`, parent is the original `private-branch`. |
| C: `git show preserve-worktree-C:…` | `tracked.txt` = `C unstaged`, `index-only.txt` = original `old`, `new.txt` = `C untracked`; parent is the original `private-branch`. |
| Before source cutover | Original branch OID, original index SHA, original branch-reflog SHA, source/root and runtime inode unchanged; no source `.jj`. |
| After cutover | Both jj workspace roots resolve; `git worktree list --porcelain` shares archive common dir; source jj `@` is an empty child of C and reports clean. |
| Runtime and original metadata | Original root and ignored DB inode stay at source; original `.git/index` and branch reflog bytes survive at the held `$old_git` path. |

The latest output uses different fixture-specific Git commit OIDs than the earlier run;
use its own [lines 12–20 and 27–39](/.test-agent/dirty-workspace-study/staged-commit-copy-first4/observations.txt)
and [lines 41–83](/.test-agent/dirty-workspace-study/staged-commit-copy-first4/observations.txt)
for its exact OIDs and final workspace checks. The tested `workspace add`
must target the **vacant** old path: jj rejects nonempty destinations
([source](/design/archive-workspace/conversion0.gpt6luna.md#what-jj-workspace-add-actually-permits)).

## Boundaries that remain

- **Two preserved commits, not identical Git staging UX.** B and C are
  independently reachable commits; the linked source Git index becomes clean
  at C and its HEAD is detached. The preexisting index's exact bytes remain
  in held old Git metadata, but the staged/unstaged status display is not
  active in the new workspace. `git diff preserve-index-B
  preserve-worktree-C` expresses their content difference; reconstructing
  an editable Git index from those revisions is a separate operation.
- **Source not deliberately written until the cutover gate.** Copying first avoids
  creating the B object, ref, or jj metadata in the source. Once cutover starts,
  the old path must change: the original Git directory is replaced by a
  linked-worktree `.git` file, and `.jj` is installed. The original Git
  directory survives separately, but has not been tested as a standalone
  rollback after a future workspace advancement. Quiesce writers across copy,
  proof, and cutover; hashes alone do not make a live copy consistent.
- **Whole-copy cost and ignored duplication.** The simple fixture uses
  `cp -a` so the archive initially contains a second ignored runtime file,
  while the original inode stays at the old path. No implicit cleanup or
  pruning is part of this route. A selective copy excluding explicitly known
  runtime paths, or a verified stage/tree construction, is an optimization
  requiring separate evidence. GNU `cp -a` is not a proof of application-level
  consistency or every filesystem/repository feature.
- **Admission and names.** Unmerged index stages and unfinished Git operations
  can make `git write-tree` fail or invalidate the model; sparse/partial
  checkouts, alternates, linked `.git` files, LFS, submodules, external
  worktrees, executable filters/fsmonitor and unusual Git config need explicit
  guards. Stage-ref creation must fail on collisions; the fixed fixture name
  is not suitable as a reusable production ref. Git status may execute
  helpers and refresh the index even with read-only intent
  ([safety review](/design/archive-toolkit/safety-review0.gpt6sol.md)).
- **Existing archive, path/failure handling.** This proof assumes an *absent*
  independent archive, a *standalone* original `.git/`, same-filesystem
  renames, and stopped writers. It does not reconcile another archive's refs,
  handle external workspace pointers, test cross-device copies or crash/power
  loss, or journal the invalid intermediate layout. Git/jj and ordinary-file
  verification before cutover are necessary but not a cross-filesystem atomic
  transaction. No automatic rollback or clean-up was tested.

## Architectural checkpoint

**Newly possible:** preserve index-only B under its *own reachable Git commit*
and final worktree C under a *different bookmarked jj/Git revision* while
keeping original local branch OIDs. A copy-first preparation can be verified
while the original source's repository/index/reflog and runtime data have not
been deliberately modified. The original source directory and runtime inodes
can then be returned to the old path with valid jj/Git workspace pointers.

**Not accomplished:** an active Git staging index at the source after
conversion, a mutation-free cutover, cross-repo archive merging, external
workspace repair, or fully recoverable crash/rollback semantics. A direct
`git commit` on the original checked-out branch does not preserve its OID;
the separate-ref commit-tree route does.

**Proposed next slice:** agree the admission/verification contract for the
copy-first *normal standalone case*: source quiescence and guarded Git
inspection, exact source/archive comparison, unique refs, optional handling
of archive-side ignored duplicates, and stop/retry checkpoints. Then exercise
at least one interrupted cutover and an original-metadata rollback in
disposable fixtures before implementing it in the Compfuzor repository task.
Only after the workspace exists should the regular dirty → upstream
availability → bookmark-if-local → advance pipeline operate on its own
workspace `@` rather than the archive root's `@`.

## Cross-references

- [Prior dirty conversion](/design/archive-workspace/dirty-conversion0.gpt6sol.md)
  — problem/evidence this study resolves by a pre-jj B commit.
- [User-directed workspace/update policy](/design/archive-workspace/direction0.gpt6astra.md)
  — dirty-fail default and independent later update/bookmark policy.
- [Clean no-copy conversion](/design/archive-workspace/conversion1.gpt6luna.md)
  — pointer-layout and root-inode precedent, with a different original-repo
  custody arrangement.
- [Archive toolkit guide](/archive/README.md#compfuzor-integration)
  — current `refresh` task integration does not perform this conversion.
