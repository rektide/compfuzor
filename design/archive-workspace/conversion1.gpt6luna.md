---
type: Design
title: No-copy checkout restoration by exchanging workspace roots and metadata
description: Tested same-filesystem rename sequence that restores the original checkout inode and ignored runtime tree at its source path after creating an archive-backed jj workspace.
resource: /design/archive-workspace/conversion1.gpt6luna.md
tags: [compfuzor, archive, jj, git, workspace, migration]
status: draft
generated: { by: model:gpt6luna, at: 2026-09-28 }
verified: { by: model:gpt6luna, at: 2026-09-28 }
stale_after: 2026-12-28
sources:
  - id: previous-inquiry
    resource: /design/archive-workspace/conversion0.gpt6luna.md
    title: Prior jj mechanics and copy-based conversion study
  - id: jj-upstream
    resource: https://github.com/jj-vcs/jj/tree/803ef00a0a6ee4ddc275d3138d5f9e7326399906
    title: Jujutsu source checkout, commit 803ef00 (0.45.1)
  - id: fixtures
    resource: /.test-agent/archive-workspace-conversion/README.md
    title: Disposable no-copy exchange fixture and evidence (gitignored)
  - id: status-safety
    resource: /design/archive-toolkit/safety-review0.gpt6sol.md
    title: Git helper/status safety review
---

# No-copy checkout restoration by exchanging workspace roots and metadata

## Result

A no-copy conversion **works in the tested scope**: a clean, plain-Git checkout,
absent canonical archive, same filesystem, and no pre-existing external Git
worktrees. Start with the whole-root move and supported jj workspace creation
from [`conversion0`](/design/archive-workspace/conversion0.gpt6luna.md), then
exchange the two directory roots and put each root's own `.git`/`.jj` entries
back where jj/Git created them. This returns the original source directory
inode, ordinary file inodes, hardlinks, ignored runtime DB/WAL/SHM, modes,
symlinks, xattrs, and contents to the source path without copying project
files. The generated workspace tree ends up at the archive root, without the
ignored runtime tree.

The exchange was applied, reversed to the valid pre-exchange layout, and
reapplied successfully in a disposable fixture **before** any source-workspace
update. Both jj workspaces reported clean, their roots resolved correctly,
Git recognized the two worktrees, the workspace-store index bytes did not
change, and a subsequent update in the source workspace left archive-main `@`
unchanged.

This advances the preferred clean-checkout topology from conversion0's
copy/overlay step. It does **not** remove the external-workspace blocker for a
checkout that already has other workspaces or Git worktrees, does not resolve
an existing-archive collision, and is not a live-service-safe atomic
transaction.

## Delta from conversion0

[`conversion0.gpt6luna.md`](/design/archive-workspace/conversion0.gpt6luna.md)
established that whole-root move plus `jj workspace add` works, but proposed
copying the original tree (including ignored files) from archive root into the
new source workspace. This wave tests the alternative suggested in follow-up:
keep those exact original filesystem objects together, and exchange roots
while transplanting only the two roots' top-level repository metadata. The
fixture used no `rsync`, `cp`, content bundle, or manually encoded Jujutsu
workspace-store edit for ordinary project files.

This document also **corrects** conversion0's statement that plain
`git status --porcelain` is a read-only dirty-input check. That wording was
overstated and should not guide an implementation. In the no-copy fixture, a
clean `git status` changed index bytes by refreshing stat-cache data; the
repository's safety review also documents clean-filter/fsmonitor execution
risks in status-like probes. Any admission check needs the project's guarded
Git execution, helper screening, and optional-lock policy, or it must fail
closed. Do not use an unguarded status query as a read-only preflight.

## Tested scope and evidence

- Installed `jj`: `0.45.1-33d3a595429b7e3b54a8ea769560247913bc8a1b`.
- Installed Git: `2.55.0`.
- Source checkout: `~/archive/jj-vcs/jj`, HEAD
  `803ef00a0a6ee4ddc275d3138d5f9e7326399906` (`0.45.1`). The binary commit
  hash differs from this source HEAD; CLI behavior below was tested with the
  installed binary. The source tree was read only.
- The starting repo was plain Git: branch `main`, an additional local branch,
  annotated tag, reflog, and one deliberately unreferenced object. The
  workspace fixtures had no existing sibling workspace/Git worktree before
  migration.
- The canonical archive path was absent. Source, archive, and hold paths were
  on one filesystem. For this follow-up wave, no production or upstream status
  query was run; all mutating/status invocations for this experiment were
  inside the disposable fixture.

The full successful reproduction and logs are in
[`rename-exchange-fixture.sh`](/.test-agent/archive-workspace-conversion/rename-exchange-fixture.sh)
and the holding-rename v6 [layout/status report](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-mv-v6/final-layout-verification.txt),
[inode/index/ref preservation checks](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-mv-v6/preservation-checks.txt),
[index refresh observations](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-mv-v6/index-observations.txt),
and [rollback/update checkpoints](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-mv-v6/checkpoint.txt).
The Linux `renameat2` alternative's [checkpoints](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-renameat2/checkpoint.txt)
and [layout report](/.test-agent/archive-workspace-conversion/rename-exchange-evidence-renameat2/final-layout-verification.txt)
also passed.
Two earlier attempts are intentionally preserved under
`rename-exchange-evidence/` and `rename-exchange-evidence-v2/`: the first had
an incorrect relative-vs-absolute Git common-dir assertion; the second's
manifest accidentally included the linked `.git` file. Both reached the
desired on-disk layout; the corrected v5 run records full checks.

## The no-copy operation

Call the archive root `A` and the former source path `S`. After the initial
whole-root move and supported workspace addition, the valid pre-exchange
layout is:

| Path | Top-level repository metadata | Ordinary working-tree files |
|---|---|---|
| `A` | Original `.git/` common repository and `.jj/repo/` shared store/main workspace | Original checkout, including ignored runtime files |
| `S` | New linked `.git` file and `.jj/repo` pointer file for the added workspace | Generated tracked checkout; ignored runtime is absent |

Exchange the **whole root directory inodes** through a holding name. Then
exchange only each root's top-level `.git` and `.jj` entries back to their
canonical roots. Use unique, absent hold names on the same filesystem; the
names below are placeholders:

```sh
# Precondition: A and S are valid, quiesced roots; all rename paths share one
# filesystem; holds are absent. No jj or Git process runs until the last move.
mv -T -- "$archive" "$root_hold"
mv -T -- "$source" "$archive"
mv -T -- "$root_hold" "$source"

# After root exchange, S has the original data/root inode plus main metadata;
# A has the generated data/root inode plus linked-workspace metadata.
mkdir -- "$metadata_hold"
mv -T -- "$source/.git" "$metadata_hold/git-main"
mv -T -- "$source/.jj" "$metadata_hold/jj-main"
mv -T -- "$archive/.git" "$source/.git"
mv -T -- "$archive/.jj" "$source/.jj"
mv -T -- "$metadata_hold/git-main" "$archive/.git"
mv -T -- "$metadata_hold/jj-main" "$archive/.jj"
rmdir -- "$metadata_hold"

# Only after all repository metadata is back at its expected path:
# inspect/verify both workspaces and resume normal commands.
```

### Linux shortcut: `renameat2(RENAME_EXCHANGE)`

There is no jj command that swaps two populated workspace roots. On this Linux
fixture, libc's `renameat2(..., RENAME_EXCHANGE)` successfully exchanged the
whole roots and the cross-type `.git`/`.jj` entries in three calls:

```text
renameat2(A,      S,      RENAME_EXCHANGE)
renameat2(A/.git, S/.git, RENAME_EXCHANGE)
renameat2(A/.jj,  S/.jj,  RENAME_EXCHANGE)
```

This removes the explicit root and metadata holding names; v6 ran the full
manifest, jj/Git status, rollback, and independent-update checks with this
mode. It does **not** avoid the logical metadata exchange: preserving the
original root directory inode at `S` first carries its `.git`/`.jj` children
to `S`, and those entries must then be exchanged back to `A`. The root inode
and its children are not independently addressable by a directory rename.
The three syscalls are individually atomic, not one transaction. After the
root exchange and after the `.git` exchange, Jujutsu's `.jj` paths still do not
match their roots; do not resume any VCS command until the `.jj` exchange also
completes. It is a Linux-specific, version-sensitive primitive, not a portable
jj interface.

The holding-rename version above uses ordinary same-filesystem renames and
explicit holds, which may be easier to journal/recover. The `renameat2`
variant is shorter but still needs the same quiescence, path checks, and
durable interruption ledger. Neither variant was crash/power-loss tested.

The intermediate layout after the three root renames is deliberately **not** a
valid state to use: root contents have swapped but metadata has not. Likewise,
the metadata-hold interval is not a VCS-operable state. Do not run `jj`, Git,
build tools, or application processes that resolve paths through either root
during these renames.

## Why the pointers remain valid

This does not rewrite Jujutsu's private workspace index or manufacture a
`.jj/repo` file. It returns the exact entries produced by jj/Git to their
original paths:

1. `jj workspace add --colocate` created `S/.jj/repo` as a relative pointer to
   `A/.jj/repo`, and `S/.git` as a Git linked-worktree pointer to the archive's
   common `.git` directory.
2. Root exchange temporarily moves those generated entries to `A` and the
   original main `.jj`/`.git` entries to `S`.
3. Metadata transplant returns the generated pointer entries to `S` and the
   original main metadata directories to `A`. Their relative paths are once
   again interpreted from the roots for which they were created.

The actual `.jj/repo` directory and Git common directory end at `A`. Therefore
the repository's workspace-store path base and Git backend's relative
`git_target` base are back where they were when `workspace add` registered the
source workspace. In the fixture, the workspace-store index hash and inode
were unchanged by the exchange; the linked `.jj/repo` and `.git` pointer bytes
were unchanged too. No hand-written workspace-store protobuf or path rewrite
was needed.

This depends on the tested shape: root workspace has `.jj/repo/` as a
directory and `.git/` as the common repo; linked workspace has `.jj/repo` as a
file and `.git` as a file. Assert those shapes and inspect pointer destinations
before doing any move. Do not assume the same internal layout on another jj
version, non-colocated workspace, external Git backend, platform, or
repository configuration.

The relevant implementation is [jj's workspace-add flow](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/cli/src/commands/workspace/add.rs#L147-L173)
and [existing-repo workspace initializer](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/lib/src/workspace.rs#L374-L413).
The loader reads a file-valued `.jj/repo` relative to the workspace `.jj`
directory ([source](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/lib/src/workspace.rs#L572-L590));
the workspace store records roots relative to the shared repo path
([source](https://github.com/jj-vcs/jj/blob/803ef00a0a6ee4ddc275d3138d5f9e7326399906/lib/src/simple_workspace_store.rs#L151-L180)).
Returning the generated link metadata to `S` and the shared repo metadata to
`A` restores those pre-existing path bases without rewriting either store.

## What the fixture actually preserved

The fixture recorded a source-tree manifest over path, type, mode, owner/group,
size, mtime, device/inode, hardlink count, file hash, symlink target, and xattr
bytes, excluding only top-level `.git` and `.jj` metadata. Before and after the
no-copy exchange it matched exactly. Specific checks confirmed:

- the original source root device/inode stayed at `S`; its owner, group, mode,
  and root xattr stayed the same;
- the original tracked files, an executable, symlink, hardlinked file pair,
  and per-file xattrs returned to `S` with their original inodes and metadata;
- ignored SQLite-like DB/WAL/SHM fixture files retained their original inode,
  bytes and xattrs at `S`, and no `.runtime/` directory remained at `A`;
- the original `.git` directory and jj repo store returned to `A`; tested Git
  refs/tag, the raw `refs/heads/main` reflog bytes, and the unreachable object
  remained present;
- `jj workspace root` resolved `default` to `A` and `source-path` to `S`;
  `jj status` was clean in both; Git showed no tracked change, with only the
  expected ignored `.jj/` and source-side `.runtime/` entries;
- reversing and reapplying the same root-plus-metadata exchange restored the
  valid pre-exchange/final states, before any source-workspace update.

The original top-level directory inode survives, but its mtime/ctime changed
while `.git` and `.jj` entries were replaced. This is an expected consequence
of changing entries in the original directory, not content loss. Open file
descriptors, process current directories, database locks, and live application
behavior were not tested; this sequence makes no live-service continuity
claim.

### Git index and status are not read-only

The original clean Git index bytes survived the rename/exchange itself and jj's
clean status queries in the fixture. A subsequent ordinary `git status` at the
archive main root changed the index hash by refreshing stat-cache entries for
the newly generated archive checkout; status at the source linked worktree
changed its separate worktree index as well. Both statuses nevertheless
reported no tracked changes. Later rollback/status restored the main index's
old stat cache when its original inode tree was back in the archive root.

Thus “same clean index state” means no staged/user-content delta was introduced
by the rename sequence, **not** byte-for-byte immunity from later status or
index refresh. Git status may update the index and can invoke filters/fsmonitor
helpers from repository config. The
[archive toolkit safety review](/design/archive-toolkit/safety-review0.gpt6sol.md#checkpoint-inventory-boundary-fixes-2026-09-28)
documents helper guards and the limits of a blanket read-only claim. A
migration preflight must reuse guarded Git execution/helper screening and
optional-lock policy, or fail closed before probing; do not improvise an
unguarded `git status` “read-only” check.

Jj status is also an operation that can snapshot filesystem state. The normal
`jj status` checks above were run only inside the disposable fixture after the
exchange and reported no change. `jj --ignore-working-copy status` is not a
replacement for a dirty-filesystem check because it explicitly ignores the
disk snapshot.

## Retry, rollback, and stopping points

The sequence has valid and invalid checkpoints:

| Checkpoint | State | Safe handling |
|---|---|---|
| After moving the original root and adding the workspace, before root exchange | Valid: `A` is the original main checkout; `S` is the new workspace | Stop here if needed. Both workspaces can be inspected. Either continue, or use the earlier copy-based design if that policy is acceptable. |
| After the root exchange, before metadata exchange/transplant completes | Invalid for jj/Git: contents and `.git`/`.jj` entries are at mismatched roots | Run no VCS/application command. Use an operation journal plus the observed hold/entry paths to finish the remaining exchanges. Do not blindly rerun the entire function. |
| After all metadata is restored | Valid final layout | Verify pointers, roots, data manifests, refs and status under the project's guarded Git/Jj procedure. Keep recovery material until accepted. |
| After inverse exchange | Valid pre-exchange layout again, if source has not diverged | The fixture proved inverse + reapply before source updates. This is not a safe automatic rollback after the source workspace has advanced. |

After a source-workspace update, reversing the exchange would move the updated
working-tree files into the archive-root tree while moving the source
workspace's metadata back to the other path. Preserve/snapshot that update
first and plan the new desired tree; do not use the inverse as an unexamined
rollback. Partial-rename restart behavior was not fault-injected; the fixture
records operation checkpoints and the required “no VCS command” interval, but
an implementation would need its own durable journal and reconciliation of
actual path presence.

## Scope boundaries

- **Primary case:** clean standalone application checkout, no canonical archive
  at the target, no other attached jj/Git workspaces, and same filesystem.
- **Dirty input:** still refuse by default. Optional snapshot-plus-bookmark is a
  separate admission decision; the tested plain-Git-to-jj initialization
  collapses staged/unstaged differences. This fixture does not make dirty
  input safe by exchanging directories.
- **Existing external workspaces/Git worktrees:** not repaired by this
  exchange. The earlier [workspace-path finding](/design/archive-workspace/conversion0.gpt6luna.md#existing-external-workspaces-are-a-migration-blocker)
  still applies when any other workspace points to the relocated repo.
- **Existing canonical archive:** not tested. First establish that the
  archive's Git/jj repo is the repository to share and handle source refs and
  objects under a separate policy; `workspace add` does not combine them.
- **Current Compfuzor development checkout:** its extant workspace/worktree
  inventory is a separate case and must not be used to assume that an old
  standalone application checkout has the same attached workspaces.
- **Other filesystems/platforms or open application handles:** not tested.
  `mv -T` is GNU/Linux-oriented, each rename must remain on one filesystem,
  and quiesced writers/processes are required. No production conversion was
  performed.

## Cross-references

- [conversion0](/design/archive-workspace/conversion0.gpt6luna.md) — prior
  `jj workspace add` mechanics, Git/Jj path invariants, dirty state, existing
  archive split, and the copy-based baseline this replaces for the tested case.
- [Archive toolkit safety review](/design/archive-toolkit/safety-review0.gpt6sol.md)
  — why Git status requires helper guards and cannot be presumed read-only.
- [Archive deployment premise](/design/archive-deployment-premise/draft0.glm53.md)
  — downstream reason to target a dedicated workspace during routine updates;
  this document only proves the structural no-copy attachment topology.

## Open decisions

1. Should migration support only standalone checkouts without linked worktrees,
   or inventory and separately repair every Git/jj workspace before the
   exchange?
2. What durable journal and rollback owner should govern the multi-rename
   interval in a future conversion tool?
3. What guarded Git probe is sufficient for a no-dirty admission check while
   detecting staged, unstaged, untracked, filters/fsmonitor, and index-refresh
   behavior without executing unsafe helpers?
4. How should a pre-existing archive's refs, reflogs, objects, and selected
   initial revision be reconciled before creating this workspace topology?
