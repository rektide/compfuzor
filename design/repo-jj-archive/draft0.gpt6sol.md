# Repository paths: archive belongs to jj

Compfuzor renders source deployments through a shared checkout. In archive mode, `SRC` and `GIT_DIR` point at the canonical `~/archive/<org>/<repo>` and `DIR/repo` links there; builds can write inside the archive. The former `repo_git.tasks` sent both archive and deployment-local repositories through Ansible's git module, whose update resets the checkout. A fail-loud guard and opt-in `GIT_UPDATE` were appropriate triage but prevented routine archive refreshes. Split the repository lane at `compfuzor.includes`: declared `REPO` plus `ARCHIVE_DOWNLOAD` selects jj; everything else selects the plain Git lane. Both continue producing `GIT_DIR` for `fs_repo.tasks`.

## Archive contract

Use `jj git clone --colocate` for absent archives, `jj git init --git-repo <existing .git>` for already-cloned Git archives, and reject non-repository directories. Use `jj git remote add/set-url`, `jj git import`, and `jj git fetch` for all transport; never call Ansible's git module or Git porcelain to reset a worktree. A declared `REPO` names `origin`, additional `GIT_REMOTES` supply peers, and `GIT_VERSION=branch@remote` selects a peer; plain `GIT_VERSION` uses `GIT_REMOTE` or origin. Default `HEAD` means main, then master; do not guess when neither exists. For a deployment that declares another branch, that branch is its selected base.

The safety ordering on an existing clone is deliberate:

1. `jj status` snapshots all non-ignored working-copy files and imports colocation's Git branches as bookmarks. Failure to snapshot aborts the render. Do not pre-reset tool-version symlinks in archive mode.
2. On a requested update, pin any nonempty `@` under a unique `harvest/<deployment>/working-copy-*` bookmark. Do not rewrite that change: it stays a durable recovery tip, including untracked files that jj snapshots. Every imported local branch retains its own bookmark. Untrack the selected remote's base *before* fetching, so jj cannot silently advance its local bookmark or abandon its old commit while deciding what to save.
3. Fetch the selected and supplemental remotes with unreachable-commit abandonment disabled. If the old base contains work not ancestral to the fetched tip, give it a unique `harvest/<deployment>/<base>-*` bookmark **before** moving the base bookmark. Then explicitly set the base bookmark to the selected remote tip and re-track it. Do not automatically push harvest refs.
4. Keep local work available in the worktree: fast-forward an empty `@` directly based on the old base; merge a dirty or divergent `@` with the new base via a new `@`, keeping the original bookmarked commit unchanged. Conflicts remain visible, not silently discarded. Do not silently prune stale artifacts or perform forced resets.

With these prerequisites `GIT_UPDATE` defaults to **true only in the archive lane**, retaining an explicit `GIT_UPDATE=false` for disconnected/no-fetch renders. The non-archive lane defaults back to true: its checkout is deployment-owned build material and the Ansible git module's dirty-tree refusal is its ordinary safe-update check; the bespoke ahead/detached guard and jj colocation do not belong there. A local branch can still be intentionally force-moved by the Git module in that lane, so users who treat DIR-local repos as personal history should opt out of updates or migrate into the archive lane.

## Notices

The jj runner returns structured notices (bookmark creation with name and full target, remote/fetch/merge and conflict events) as JSON. A task appends each notice with `set_fact` to `compfuzor_repo_notices`, notifying `Compfuzor: print repository notices`. A small imported role registers that handler without editing hundreds of playbooks. Ansible automatically flushes notified handlers after the play's task section, rather than printing per-event midway through a render. The handler emits a visually distinct `BOOKMARK CREATED  <name> -> <target>` line; ordinary notices use `REPO NOTICE ...`. No notice means no handler invocation. Handler registration precedes repository work and works with playbooks that also declare their own handlers.

## Tradeoffs and boundary

- Not Ansible git followed by `jj git import`: Git's reset happens before jj can reliably snapshot and label it. Import afterward cannot reconstruct ignored/untracked overwritten state.
- Not Git bundles on every render: jj snapshots plus separately named bookmarks preserve the visible work locally without cloning every object twice. For disaster recovery after loss of the archive directory, backups or an explicit push of harvest refs are still necessary; this workflow does **not** promise host-failure resilience.
- No implicit push, prune, forced conflict resolution, submodule recursion, or shallow-fetch depth changes in the jj lane. Surface unsupported `GIT_SUBMODULES` / `GIT_DEPTH` requests rather than silently claiming parity; follow-on work can add those after testing their jj equivalents and safety.
- A concurrent human mutating the *same* archive during a render is outside this serialization contract. `jj` operations and the checkout should not race other writers.

## Cross-references

- [`script/harvest-legacy-repo.sh`](/script/harvest-legacy-repo.sh) is the standalone legacy-checkout migration precedent: namespaced branches and a working-copy recovery tip. The archive lane operates in-place without deleting a legacy deployment directory or making safety bundles.
- [`tasks/compfuzor/vars_src.tasks`](/tasks/compfuzor/vars_src.tasks), [`tasks/compfuzor/fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks), and [`vars/common.yaml`](/vars/common.yaml) establish the source path and downstream symlink contracts.
- [`tasks/compfuzor/vars_repo.tasks`](/tasks/compfuzor/vars_repo.tasks) formerly removed symlinks ahead of repository update; in archive mode it must not run before the jj snapshot.
