---
type: VerificationCheckpoint
title: Selected-archive alias cutover implementation and fixture verification
description: Narrow automatic deployment-alias migration, guarded preflight, exact-link recovery, and source/bundle regression results.
tags: [archive, deployment, jj, git-worktree, tdd]
status: draft
generated: { by: 'model:openai/gpt-6.1-sol', at: '2026-09-29' }
sources:
  - resource: /design/archive-deploy-layout/migration0.gpt61sol.md
    title: Accepted operator scope and public CLI regression boundary
  - resource: /archive/src/repository/deploy.ts
    title: Alias admission, cutover, and recovery
  - resource: /tests/integration/repo_jj_archive.test.py
    title: Disposable repository CLI integration fixtures
---

# Situation and accepted boundary

The operator authorized replacing the legacy deployment `repo` alias of its
selected archive with a dedicated jj workspace and colocated Git worktree.
The accepted seam is the existing deploy CLI integration suite, not a new live
Ansible or service operation. The [implementation brief](/design/archive-deploy-layout/migration0.gpt61sol.md)
records this authorization; the [diagnosis](/design/archive-deploy-layout/diagnosis0.gpt61sol.md)
remains the historical account of the old refusal.

# What changed

[`deployWorkspace`](/archive/src/repository/deploy.ts) admits only a
**final-component symlink whose canonical target is the selected validated
archive**. It resolves the intended replacement location through its parent,
without following the old final link. Lexical and canonical nesting remain
refused. Both relative link targets and symlinked archive roots are supported.

Before unlinking, archive health is queried read-only, refresh options are
validated using the checks shared with [`refreshArchive`](/archive/src/repository/refresh.ts),
declared remote URLs are checked under the existing reconciliation policy,
and the selected remote branch must be available and non-conflicted. A
conflicted selected local bookmark also blocks alias cutover. Immediately
before removal, device/inode identity, exact link text, canonical target, and
canonical parent location are rechecked.

The existing `jj workspace add --colocate` operation creates the dedicated
workspace; ordinary deployment refresh then runs there. A notice identifies
the replaced archive symlink. Archive main is not refreshed as a workaround.
Workspace creation may snapshot its previously unsnapshotted work once under
jj's existing semantics; archive contents and saved tips are retained.

The alias-parent fixture exposed an existing idempotence bug: `jj workspace
root` reports the physical path, but admission compared it with the lexical
CLI spelling. Admission now compares against the already canonicalized
workspace location. Repository-pointer and Git-worktree ownership checks are
unchanged; symlinks to unrelated repositories or even to another child
workspace of the selected archive still do not qualify for replacement.

## Failure and recovery boundary

If `jj workspace add` fails **without creating a destination entry**, restore
the exact original symlink text, including a relative target, and rethrow the
creation error. Symlink creation itself refuses a newly occupied destination;
if recovery fails, the reported aggregate retains both errors.

If any entry exists after failed creation, leave it untouched. No partial
directory, `.jj` metadata, Git worktree registration, or stale artifact is
deleted. Even when the link is restored, jj may have left registration state
that requires deliberate investigation before retrying. This is a guarded
cutover, not an atomic filesystem or repository transaction: keep writers
stopped and paths stable.

Custom `GIT_DIR` exposure through [`fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks)
is unchanged. No live deployment, archive, composed build source, binary, or
service was modified. Initial user changes in `.beads/issues.jsonl`,
`hyalo.src.pb`, `script/harvest-legacy-repo.sh`, and
`tasks/compfuzor/sub_status_proc.tasks` were not changed or committed.

# Red → green evidence

Each discovered behavior below was established at the public CLI seam before
its implementation change. Failures use empty stdout and a nonzero status.

| Regression | Observed red | Green result and implementation commit |
|---|---|---|
| Selected archive alias becomes a dedicated workspace | Exact old `is occupied; move it aside or clean it up manually before creating a jj workspace` failure | 1 passed; `c376aab5` |
| Invalid refresh options leave the alias intact | CLI failed correctly, but the alias had already become a directory | 1 passed across update/fetch/untrack/depth/submodules cases; `c5a8013d` |
| Conflicted selected local bookmark leaves the alias intact | Refresh reported the conflict after replacing the alias | 1 passed; `3e0fad4d` |
| Missing jj-visible archive history leaves the alias intact | Workspace creation failed after unlinking | 1 passed; `62e63990` |
| Failed creation with no destination restores the exact alias | Injected external jj failure left the path absent | 1 passed, including successful retry; `61e31c4f` |
| Canonical parent alias remains idempotent | First migration succeeded; second deploy refused the physical workspace root | 1 passed; `cbcac0a5` |
| Copied launcher and bundle migrate without dependencies | Old shipped bundle reproduced the exact occupied-path failure | 1 passed after documented build; `6374b85c` |

Additional protected-edge fixtures pass for unrelated/dangling links, a link
to a different child workspace, unavailable/undeclared branches or remotes,
invalid declared URLs, lexical/canonical nesting, a changed link during
preflight, and partial-state preservation. A selected `release@peer` fixture
proves the new deployment uses the declared remote branch without switching
archive main. Archive tracked edits, untracked work, ignored runtime bytes,
saved tips, `.jj/repo` pointer ownership, `.git` pointer files, subsequent
refresh isolation, and idempotence are covered. External-process fault tests
intercept only selected jj invocations and otherwise delegate to real jj.

# Final checks

```sh
pnpm check
node --test 'archive/test/**/*.test.ts'
python3 -m pytest --import-mode=importlib -q \
  tests/integration/repo_jj_archive.test.py \
  tests/integration/archive_library.test.py \
  tests/integration/archive_cli_contract.test.py \
  tests/integration/archive_custody_cli.test.py
pnpm build
```

- `pnpm check`: formatting, lint, and `tsgo --noEmit` pass without warnings.
  An earlier formatting failure and then a validation-helper lint warning were
  corrected before the final successful check.
- Archive Node suite: **127 passed**, zero failures, cancellations, or skips.
- Four-file archive integration suite: **60 passed**, including the full
  `repo_jj_archive.test.py` file and existing jj-only child colocation tests.
  Python's installed plugins emit pre-existing `SyntaxWarning` notices.
- `pnpm build`: passes; the committed single-file archive distribution was
  regenerated from source, with no dependency or package-manifest changes.
  The build's dependency-bundling hint is informational.

# Cross-references

- [Accepted migration brief](/design/archive-deploy-layout/migration0.gpt61sol.md):
  authorization, selected-archive-only boundary, and confirmed test seam.
- [Original diagnosis](/design/archive-deploy-layout/diagnosis0.gpt61sol.md):
  pre-change evidence and explicit separation from OpenCode's composed build.
- [Maintained toolkit README](/archive/README.md#compfuzor-integration):
  current automatic cutover policy, recovery limitation, and custom exposure
  boundary. This explanation supersedes only the old alias policy, not the
  broader distinction between deployment and custody.
- [CLI integration tests](/tests/integration/repo_jj_archive.test.py):
  executable fixture evidence through source, real launcher, and copied bundle.
