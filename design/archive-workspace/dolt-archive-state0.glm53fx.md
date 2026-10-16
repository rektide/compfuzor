---
type: Investigation
title: Dolt archive dirty working-copy state — forensic assessment before workspace conversion
description: The 2,235 dirty entries in the dolthub/dolt archive were CIFS executable-bit presentation phantoms, not content; the archive is currently clean and the dolt workspace conversion can proceed behind a cheap mode preflight.
resource: /design/archive-workspace/dolt-archive-state0.glm53fx.md
tags: [compfuzor, archive, dolt, jj, git, cifs, file-modes, deploy]
status: draft
generated: { by: model:glm5.3-flash-max, at: 2026-10-16 }
verified: { by: model:glm5.3-flash-max, at: 2026-10-16 }
sources:
  - id: commissioning
    resource: opencode://ses_eba42c532ffeGDFn343ysNvjcd
    title: Commissioning session for the dolt archive state assessment
  - id: authoring-session
    resource: opencode://ses_eba29bf32ffeoUpRhWDhk3K21z
    title: Forensic assessment of the dolt archive dirty working-copy state; authoring session for this document
  - id: saved-status
    resource: /tmp/opencode/dolt-status.txt
    title: Saved `git status --porcelain` of the archive, written 2026-10-16 17:41:18 UTC
  - id: archive-repo
    resource: /mnt/bitblaster/archive/dolthub/dolt
    title: dolthub/dolt archive repository — read-only git/jj queries enumerated in Evidence
  - id: proc-mounts
    resource: /proc/mounts
    title: Client mount table for //nanomachine/bitblaster (CIFS) and its NFS twin
  - id: archive-readme
    resource: /archive/README.md
    title: Archive toolkit operator guide
  - id: conversion
    resource: /design/archive-workspace/conversion0.gpt6luna.md
    title: Converting a standalone checkout into an archive-backed jj workspace
---

# Dolt archive dirty working-copy state — forensic assessment before workspace conversion

## Result

**The 2,235 ` M ` entries were a mass executable-bit phantom from CIFS mode
presentation. No content in the archive was ever modified, and nothing of ours
created them.** The archive is currently completely clean: worktree = index =
HEAD = `main` = `origin/main` at `d0e0a56a5bd675e71a3be1efb271c59dbb745807`
(upstream merge PR #11331, committed 2026-07-20). There are no untracked files,
no staged entries, no stash, no local branches, and jj's recorded working copy
is an empty commit on `main`.

**dolt conversion can proceed.** deploy's one-time archive snapshot would
currently absorb nothing. Because the underlying condition (CIFS mode
presentation) is environmental and can return, run the cheap preflight in
[Implications](#implications-for-the-pending-dolt-workspace-conversion)
immediately before `deploy`.

Confidence:

- **High** that there is no content change and no local work to preserve:
  current status is empty against a HEAD explained end-to-end by the reflog;
  every sampled and full diff is empty; mtime/ctime history shows no file
  writes since the 2026-09-19 reorganization.
- **Medium** on the exact mechanism of today's transient: the client-side
  view flipped from "everything appears 0755" to real server modes
  (664/775) between 17:41:18 and ~17:52 UTC today. The server side cannot be
  inspected from here, and one 20-file residue (below) is not fully explained.

## Evidence

All commands were read-only for repository content, refs, and worktree. Git
status/diff runs perform their routine index stat-cache refresh (`.git/index`
rewritten 17:41:18 by the commissioning session's status run, and again by my
verification runs) — the same read-side side effect as the saved status
itself; no content, ref, or worktree file was touched. jj commands were run
with `--ignore-working-copy` throughout.

**Archive state now (2026-10-16 ~17:45–18:05 UTC):**

| Check | Command | Result |
|---|---|---|
| Saved status composition | `awk '{print substr($0,1,2)}' /tmp/opencode/dolt-status.txt \| sort \| uniq -c` | 2235 lines, 100% ` M ` (unstaged worktree-modified); zero `??`, zero staged. Top-level spread: go 1599, integration-tests 537, .github 68, proto 17, docker 4, images 3, plus top-level files (README.md, LICENSE, .gitmodules, …). |
| Tracked inventory | `git ls-files \| wc -l`; `git ls-files -s \| awk '{print $1}' \| sort \| uniq -c` | 2418 tracked files: 2255 × `100644`, 163 × `100755`, no symlinks/submodules. Arithmetic closes: 2418 − 163 (index-exec) − 20 (residue, below) = **2235** — the dirty set is exactly "every index-100644 file". |
| filemode setting | `git config --show-origin --show-scope core.filemode` | `local file:.git/config true` |
| Sample content diffs | `git diff -- README.md .github/FUNDING.yml go/.gitignore proto/.bazelrc integration-tests/bats/.gitignore` | **No output** — no hunks, not even mode lines, by ~17:45. |
| Full worktree status | `git status --porcelain` | **0 lines.** |
| Full diff vs HEAD | `git diff HEAD`; `git diff HEAD --summary` | Empty (a `--stat \| tail` at ~17:48 still showed 3 mode-only entries — README.md, .github/FUNDING.yml, proto/.bazelrc, `0 insertions, 0 deletions` — gone by ~17:52; see the flip timeline below). |
| Modes on disk | `stat -c '%a %y %n' …` on README.md, FUNDING.yml, proto/.bazelrc, .github/scripts/fuzzer/run-fuzzer.sh, go/.gitignore, a noms fixture | Non-exec files **664**, exec scripts **775** — real unix modes with group-write; exec bits match the index's 163 `100755` entries exactly. |
| Change times | `stat -c '%a %z %y %n' …` | ctime uniform **2026-09-19 07:27:52–55 UTC** across all sampled files; mtimes preserved (Mar 4 / Jul 9, 2026). A 3-second tree-wide ctime wipe = the archive reorganization (matching the `~/archive/dolthub/*` symlinks re-created the same day). No chmod since — a chmod would have bumped ctime to today. |

**History and position:**

| Check | Command | Result |
|---|---|---|
| Reflog | `git reflog --date=iso \| head -40` | clone from github **2026-03-04 04:40 UTC**; two resets to origin/main Mar 4; `pull --ff-only` fast-forward **2026-07-09** → `d1da417d27`; `pull --ff-only` fast-forward **2026-07-21 02:23 -0400** → `d0e0a56a5b`. Nothing since. |
| Last fetch | `stat .git/FETCH_HEAD .git/logs/HEAD` | Both **2026-07-21 06:23:57 UTC** — matches the last pull exactly. |
| Position | `git rev-parse HEAD main origin/main` | All three = `d0e0a56a5b…`. `git branch -avv`: only `main` tracking `origin/main`, no local branches. |
| Stash / worktrees | `git stash list`; `git worktree list` | Both empty / single main worktree at the archive path. |
| jj operations | `jj --ignore-working-copy -R <archive> op log --limit 30` | workspace add + `jj git init` + `jj bookmark track main@origin` ≈3 months ago (matches the late-July clone/init); two `jj --quiet util snapshot` import-git-refs ops ≈2 months ago (≈ mid-August 2026). **No jj operation since.** |
| jj recorded working copy | `jj --ignore-working-copy -R <archive> status` | "The working copy has no changes." `@` = `zmlxpmlp a36a0d57` (empty), parent = `main` `d0e0a56` — jj's recorded tree already equals `main`. |

**Mount environment:** `/proc/mounts` shows `//nanomachine/bitblaster` on
`/mnt/bitblaster` as CIFS SMB 3.1.1 with `posix,posixpaths` (SMB POSIX
extensions — real unix modes pass through when the server honors them, making
the configured `file_mode=0755` a fallback for when it does not),
`multichannel,max_channels=4`, `actimeo=10`. The same server directory is
additionally mounted via NFS 4.2 at `/mnt/nfs-bitblaster`. The task brief's
"when the server honors unix extensions the real modes come through, otherwise
everything appears 0755" is exactly the observed flip surface.

**Timeline of today's flip (all UTC):** 17:41:18 commissioning `git status`
writes the saved file (2235 × ` M `) and refreshes `.git/index` in the same
second; ~17:45 my sampled diffs show nothing; ~17:48 `diff HEAD --stat` shows
3 residual mode-only entries; ~17:52 `diff HEAD --summary` empty. The
executable-bit presentation drained to the real server view within ~10
minutes, consistent with SMB negotiation/channel (`multichannel`) or attribute
cache state converging after a change server-side or a remount.

**Residual anomaly, disclosed:** 20 index-`100644` files were clean already in
the 17:41 snapshot — all of them noms test-fixture database files
(`go/cmd/dolt/commands/testdata/signed_commits/db/.dolt/noms/*`,
`integration-tests/bats/{json-oldformat-repo,performance-repo}/.dolt/noms/*`).
They carry no `assume-unchanged`/`skip-worktree` bits
(`git ls-files -v` has no lowercase entries) and their modes today (664) match
their index entries. Under a strict "everything appeared 0755" window they
should also have been dirty; their early cleanliness suggests the flip was
already partially in progress at 17:41 (mixed views across channels/lookups).
This does not affect any conclusion: their content is identical to HEAD like
everything else.

**`??` discrepancy:** the commissioning notes mention "a handful of `??`"
entries, but the saved file contains none; the 156 MB stale `go/dolt` build
binary (dated 2026-03-04) it describes was deleted earlier today by the
commissioning session, and current status confirms **zero untracked files**
now. The saved file is treated as authoritative for what it contains.

## Answers to the three questions

**1. What are these changes?** A mode-only phantom. The dirty set is exactly
the index's `100644` files minus 20, under `core.filemode=true`, on a CIFS
mount whose fallback presentation (`file_mode=0755`) makes every file appear
executable when SMB POSIX extensions are not being honored. Git reports an
exec-bit difference as ` M ` even when content is byte-identical, which is
why the list was 100% unstaged ` M ` with no hunks. jj models the executable
bit as content, which is why jj wanted to snapshot everything during the
phantom window. The phantom window ended today between 17:41 and ~17:52; the
real server modes (664/775) match the index exec bits and the tree is clean.

**2. Are they build artifacts?** No. There are no untracked files at all now,
and tracked-file modifications were never content: the only known build
artifact was the untracked 156 MB `go/dolt` binary (2026-03-04), already
deleted today, which was a snapshot blocker (jj refuses files > 1 MB) but not
one of the ` M ` entries. Generated sources (proto/flatbuffers, .github action
dist bundles) appear in the saved list only as phantom mode entries; none were
regenerated or hand-edited.

**3. Did we do anything here?** No. The repository's entire local history is:
clone 2026-03-04, two `pull --ff-only` fast-forwards (Jul 9, Jul 21), and jj
init/track/snapshot-import operations in late July and mid-August 2026. There
are no local commits, branches, stashes, or edits; ctime/mtime evidence shows
no file writes since the 2026-09-19 07:27 UTC re-materialization of the tree
(the archive reorganization that also recreated `~/archive/dolthub/*`). The
dirty state was a transient client-side view, not work by any person or agent.
The Sep 19 rebuild gave the tree umask-flavored modes (664/775) that happen to
preserve the index's exec-bit semantics, so even after the reorganization git
and jj had a clean view — until the presentation flipped.

## Implications for the pending dolt workspace conversion

- **What deploy's snapshot would absorb: nothing.** Per
  [the archive guide](/archive/README.md#compfuzor-integration), creating a
  workspace from an existing archive may snapshot previously unsnapshotted
  files in the archive main `@` once. jj's recorded `@` is an empty commit on
  `main` and the disk matches the recorded tree, so a snapshot today is a
  no-op (it would not even change `@`). The `go/dolt` >1 MB blocker is gone,
  and zero untracked files remain.
- **Preflight immediately before `deploy`** (the condition is environmental
  and can return with mount/server state):

  ```sh
  git -C /mnt/bitblaster/archive/dolthub/dolt status --porcelain | wc -l
  # expect 0; thousands of entries = phantom window, stop and re-check later
  stat -c '%a' /mnt/bitblaster/archive/dolthub/dolt/README.md   # expect 664
  stat -c '%a' /mnt/bitblaster/archive/dolthub/dolt/.github/scripts/fuzzer/run-fuzzer.sh  # expect 775
  jj --ignore-working-copy -R /mnt/bitblaster/archive/dolthub/dolt status
  # expect "The working copy has no changes."
  ```

- **Do not "fix" anything by setting `core.filemode=false`.** The modes now
  coming through are genuine; disabling filemode would mask real exec-bit
  changes forever, and it would not help jj anyway (jj models exec bits as
  content independently of git's config).
- **If a future phantom is accidentally snapshotted**, the damage is bounded
  and mechanical: the snapshot commit would contain exec-bit-only changes to
  thousands of files; restoring `@` from its parent recovers cleanly. The
  preflight is cheaper than the cleanup.
- **Mind the twin mount.** The same server directory is also NFS-mounted at
  `/mnt/nfs-bitblaster`. Run all git/jj for this repo through the canonical
  `/mnt/bitblaster/...` path that compfuzor deploys against, and never
  concurrently through both paths.

## Cross-references

- [Archive toolkit operator guide](/archive/README.md#compfuzor-integration) —
  deploy's workspace-creation semantics, including the one-time snapshot of
  the archive main `@`; `health` is read-only and does not inspect dirty
  state.
- [Conversion research wave](/design/archive-workspace/conversion0.gpt6luna.md) —
  the dirty-state admission gate and the tested fact that
  `jj --ignore-working-copy status` reports the recorded working copy, not the
  disk; this document applies both to the archive side of a real conversion.
