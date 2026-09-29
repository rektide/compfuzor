---
type: Diagnosis
title: OpenCode deployment still aliases its archive
description: The new dedicated jj/Git deployment workspace rejects the previous repo symlink layout before fetching or refreshing.
tags: [archive, deployment, jj, git-worktree, opencode]
status: draft
generated: { by: 'model:openai/gpt-6.1-sol', at: '2026-09-29' }
sources:
  - resource: /archive/src/repository/deploy.ts
    title: Deployment admission and workspace creation
  - resource: /tasks/compfuzor/repo_jj_archive.tasks
    title: Compfuzor archive deployment invocation
  - resource: /opencode.src.pb
    title: OpenCode deployment and separate composed build source
---

# Situation

After rebuilding the OpenCode archive, running `opencode.src.pb` fails at
`tasks/compfuzor/repo_jj_archive.tasks:45`. Its `deploy` invocation targets
`/usr/local/src/opencode-git/repo`, backed by
`/home/rektide/archive/anomalyco/opencode`, selecting `working@rektide`.
The operator specifically notes that Git-worktree support is new in `archive/`.

The diagnostic question is whether this is archive corruption, a workspace
registration problem, or a mismatch between the old deployment layout and the
new admission rules. This inquiry does not authorize migration or service changes.

# Confirmed cause

The live path layout on 2026-09-29 is:

```text
/opt/opencode-git -> /usr/local/src/opencode-git
/usr/local/src/opencode-git/repo -> /home/rektide/archive/anomalyco/opencode
```

The deployment's `repo` is an old alias of the **main archive checkout**, not a
dedicated child workspace. Access through `/opt` reaches the same symlink.

[`deployWorkspace`](/archive/src/repository/deploy.ts) uses `lstat` for the
workspace entry (lines 15–21, 81–86). A symlink is not a directory according to
that check, so it throws the exact reported occupied-path error. This precedes
remote reconciliation, fetching, and workspace creation. An Ansible task or
TypeScript-launcher failure is not the underlying cause.

Simply allowing this symlink would not make the layout valid: canonical archive
and workspace paths would be identical, which the next guard explicitly rejects
(lines 87–93). The separate-workspace boundary is architectural, not just an
overly restrictive file-type check.

Existing **child jj workspaces without Git colocation** are supported: the
admission check verifies `.jj/repo` points to the shared archive, verifies the
workspace root, and enables Git colocation when `.git` is absent (lines 98–142).
That upgrade path does not apply to an alias of the archive's main workspace.

# Feedback loop and live evidence

The disposable reproduction is
`.test-agent/opencode-archive-diagnosis/reproduce.py`. It prepares a local
Git/jj archive, makes a deployment symlink to it, invokes the real compatibility
launcher, checks exit 1 and the exact occupied-path diagnostic, and checks that
the symlink remains intact. It reproduced the failure twice without network
access or mutations to the live archive:

```text
rc=1
repo-jj-archive: <scratch>/deployment/repo is occupied; move it aside or clean it up manually before creating a jj workspace
REPRODUCED: archive symlink is refused and left intact
```

Additional live read-only observations:

- `node archive/src/repo-jj-archive.ts health --dest /home/rektide/archive/anomalyco/opencode`
  reports `Visible heads OK; no conflicted bookmarks`. This is not a full
  integrity check or a guarantee about every workspace.
- The archive's Git worktree list and jj workspace list do not contain a
  dedicated Compfuzor OpenCode deployment at the failing path.
- `refs/remotes/rektide/working` exists locally at
  `960ed25d1d6ba2db7e20349e0b7f98c04460a064`.
- The declared `origin` and `rektide` remote URLs match the playbook.
- `~/src/opencode-working` is a separate registered jj workspace. Its health
  check also passes; `.jj/repo` points into the rebuilt archive. It currently
  lacks `.git`, so it is not yet a Git-colocated workspace.
- `/usr/local/bin/opencode` points to the binary under
  `~/src/opencode-working/packages/cli/dist/cli-linux-x64/bin/opencode`.

These findings eliminate stale registration as the cause of **this refusal**:
the entry-type guard fails before registration is inspected. They do not claim
all consequences of the archive rebuild have been resolved.

# Migration direction, not yet applied

The existing archive remains the shared repository. After explicit operator
approval, preserve/move aside **only the old deployment `repo` symlink**, leaving
its archive target untouched. The now-absent deployment path lets `deploy`
create a real jj workspace with `jj workspace add --colocate`, selecting
`working@rektide`. Do not rename the archive through the symlink, remove its
contents, or automatically prune workspace metadata.

An alternate path can be selected through `GIT_DIR` rather than moving the
symlink, but its downstream source-path assumptions need consideration. Neither
choice should silently redirect the existing composed build workspace.

The playbook's build/install source is explicitly `OPENCODE_WORKING_DIR`, not
the deployment `repo`. Fixing this refusal does **not** by itself change the
composition, rebuild the binary, or restart the service. Adding Git colocation
to `~/src/opencode-working` is a separate operation and is not required to
explain the current task failure. In particular, do not point `deploy` at that
working workspace merely to bypass the error: `deploy` also refreshes/reconciles
its selected checkout, rather than only adding `.git` metadata.

# Cross-references

- [Archive toolkit overview](/archive/README.md): distinguishes maintenance
  and active checkout changes from custody, publication, and retirement;
  `--update false` is explicitly not a dry run.
- [Compfuzor deployment task](/tasks/compfuzor/repo_jj_archive.tasks): shows
  `ARCHIVE_SRC` and deployment workspace are now distinct CLI inputs and keeps
  the original runner diagnostic intact on failure.
- [Deployment integration tests](/tests/integration/repo_jj_archive.test.py):
  cover real colocated deployment workspaces, upgrading jj-only child
  workspaces, rejecting occupied unrelated paths, and canonical nested-path
  guards. The exact old deployment-to-archive symlink is reproduced separately
  in the diagnostic scratch harness.
- [OpenCode playbook](/opencode.src.pb): `OPENCODE_WORKING_DIR` selects the
  composed workspace for builds and global binary links, independently of the
  generic repository deployment lane.

# Addendum: migration tested in the disposable reproduction

The same scratch harness now moves its disposable `repo` symlink to
`repo.archive-link` and repeats the identical `deploy` invocation. This succeeds
and creates a directory with `.jj/repo` and `.git` pointer files. The saved
symlink still resolves to the original archive. Thus the proposed layout change
has an observed failing-to-passing signal, not only a code-reading rationale:

```text
VERIFIED IN FIXTURE: moving only the link permits a dedicated colocated deployment
```

This is fixture verification only. The live deployment symlink, archive,
composed build workspace, binaries, and services remain unchanged.

# Addendum: operator-approved automatic migration

The operator subsequently requested automatic replacement specifically for the
deployment `repo` symlink that resolves to its selected archive. The
[implementation brief](/design/archive-deploy-layout/migration0.gpt61sol.md)
records this narrower exception to the original refusal policy, the agreed CLI
test seam, and the safety constraints. This diagnosis describes the pre-change
behavior; it is not an argument against that authorized migration.

The follow-up investigation also narrows the alternate-path suggestion above:
[`fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks) refuses a custom `GIT_DIR`
exposure while `DIR/repo` still points to the old archive. A custom path alone
does not bypass that guard. Automatic migration here is scoped to the reported
default deployment path, not a change to the separate exposure-link policy.
