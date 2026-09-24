# Repository paths: archive belongs to jj

Compfuzor renders source deployments through a shared checkout. In archive mode, `SRC` and `GIT_DIR` point at the canonical `~/archive/<org>/<repo>` and `DIR/repo` links there; builds can write inside the archive. The former `repo_git.tasks` sent both archive and deployment-local repositories through Ansible's git module, whose update resets the checkout. A fail-loud guard and opt-in `GIT_UPDATE` were appropriate triage but prevented routine archive refreshes. Split the repository lane at `compfuzor.includes`: declared `REPO` plus `ARCHIVE_DOWNLOAD` selects jj; deployment-local clones use plain Git. Auxiliary `REPOS` declarations remain DIR-local even when the primary `REPO` is archived (e.g. `ansible.src.pb`); `repo_git.tasks` omits the primary in that case. This corrects the old placement of those auxiliary checkouts inside the primary archive, where builds could accidentally snapshot them. Both continue producing `GIT_DIR` for `fs_repo.tasks`.

## Archive contract

Use `jj git clone --colocate` for absent archives, `jj git init --git-repo <existing .git>` for already-cloned Git archives, and reject non-repository directories. Use `jj git remote add/set-url`, `jj git import`, and `jj git fetch` for all transport; never call Ansible's git module or Git porcelain to reset a worktree. A declared `REPO` names `origin`, additional `GIT_REMOTES` supply peers, and `GIT_VERSION=branch@remote` selects a peer; plain `GIT_VERSION` uses `GIT_REMOTE` or origin. Default `HEAD` means main, then master; do not guess when neither exists. For a deployment that declares another branch, that branch is its selected base.

The safety ordering on an existing clone is deliberate:

1. `jj status` snapshots all non-ignored working-copy files and imports colocation's Git branches as bookmarks. Failure to snapshot aborts the render. Do not pre-reset tool-version symlinks in archive mode.
2. On a requested update, duplicate any nonempty `@` under a unique `harvest/<deployment>/working-copy-*` bookmark. The duplicate has a separate change ID, so subsequent edits to the live `@` cannot move the recovery bookmark; it retains untracked files that jj snapshots. Every imported local branch retains its own bookmark. Untrack tracked local bookmarks *before* fetching, so jj cannot silently advance or abandon their old commits while deciding what to save.
3. Fetch the selected and supplemental remotes with unreachable-commit abandonment disabled. If the old base contains work not ancestral to the fetched tip, give it a unique `harvest/<deployment>/<base>-*` bookmark **before** moving the base bookmark. Then explicitly set the base bookmark to the selected remote tip and re-track it. Do not automatically push harvest refs.
4. Keep local work available in the worktree: fast-forward an empty `@` directly based on the old base; merge a dirty or divergent `@` with the new base via a new `@`, keeping the original bookmarked commit unchanged. Conflicts remain visible, not silently discarded. Do not silently prune stale artifacts or perform forced resets.

With these prerequisites `GIT_UPDATE` defaults to **true only in the archive lane**, retaining an explicit `GIT_UPDATE=false` for disconnected/no-fetch renders. The non-archive lane defaults back to true: its checkout is deployment-owned build material and the Ansible git module's dirty-tree refusal is its ordinary safe-update check; the bespoke ahead/detached guard and jj colocation do not belong there. A local branch can still be intentionally force-moved by the Git module in that lane, so users who treat DIR-local repos as personal history should opt out of updates or migrate into the archive lane.

## Notices

The jj runner returns structured notices (bookmark creation with name and full target, remote/fetch/merge and conflict events) as JSON. A task appends each notice with `set_fact` to `compfuzor_repo_notices`, notifying `Compfuzor: print repository notices`. A small imported role registers that handler without editing hundreds of playbooks. Ansible automatically flushes notified handlers after the play's task section, rather than printing per-event midway through a render. The handler emits a visually distinct `BOOKMARK CREATED  <name> -> <target>` line; ordinary notices use `REPO NOTICE ...`. No notice means no handler invocation. Handler registration precedes repository work and works with playbooks that also declare their own handlers.

## Tool-version links in the archive

`gen_tool_versions.tasks` emits the deployment-owned `DIR/.tool-versions` or `DIR/mise.toml` and, when requested, a link in the archive repo root. The root link is necessary because asdf/mise follow the physical cwd through `DIR/repo`, never seeing the deployment file above that symlink. Existing archives overwhelmingly already track their own version-manager files; a preserve-policy link into those paths would fail the render. A synthetic link into an untracked path otherwise pollutes Git and jj `@` on every render.

Split this decision across the two phases that actually know the facts:

1. `gen_tool_versions.tasks` *declares* the repo-root link for a primary archive even before the initial clone exists (not for bypassed links). It does not inspect the repository or remove the deployment-side generated file.
2. Before the archive runner first snapshots an existing worktree (and before `jj git init` on an existing plain Git clone), write just the declared link basename to this clone's `.git/info/exclude`, idempotently. jj 0.45.1 and Git both honor that file for **untracked** paths. It is local per clone, never committed/pushed. Even when upstream tracks a same-named file, the exclude is harmless: tracked files are not made invisible by ignore rules.
3. After fetching, inspect the selected upstream commit's tree with `jj file list`. If it tracks the intended link path, return a structured `repo-owned-version` notice and the destination as a skip; Ansible removes the record from the already-compiled deferred link plan before it can be applied. The notice handler distinctly prints `REPO OWNS VERSION CONFIG  <path> (link skipped)`. If the path is untracked but occupied by a different local object, preserve that object and skip as well; never force a generated link over it. When an older generated symlink was already snapshotted, the exclude alone is insufficient; if its target is the deployment file, run `jj file untrack <basename>` *after* installing the exclude. jj rejects untracking nonignored paths, which is a useful safety check. Preserve any genuine local edits to tracked upstream version config as archive work, but never turn those upstream-owned files into deployment links.

This belongs in the archive repository lane, **not only** in generation: generation runs before the repository clone/fetch and cannot know what upstream tracks, especially on the initial clone or after an upstream update. Conversely, the archive lane should not invent version-manager intent: it consumes the compiled tool-version link declaration, which is the generator's domain. No global ignore or pruning of arbitrary repo content is implied.

## Tradeoffs and boundary

- Not Ansible git followed by `jj git import`: Git's reset happens before jj can reliably snapshot and label it. Import afterward cannot reconstruct ignored/untracked overwritten state.
- Not Git bundles on every render: jj snapshots plus separately named bookmarks preserve the visible work locally without cloning every object twice. For disaster recovery after loss of the archive directory, backups or an explicit push of harvest refs are still necessary; this workflow does **not** promise host-failure resilience.
- No implicit push, prune, forced conflict resolution, submodule recursion, or shallow-fetch depth changes in the jj lane. Surface unsupported `GIT_SUBMODULES` / `GIT_DEPTH` requests rather than silently claiming parity; follow-on work can add those after testing their jj equivalents and safety.
- A concurrent human mutating the *same* archive during a render is outside this serialization contract. `jj` operations and the checkout should not race other writers.

## Cross-references

- [`script/harvest-legacy-repo.sh`](/script/harvest-legacy-repo.sh) is the standalone legacy-checkout migration precedent: namespaced branches and a working-copy recovery tip. The archive lane operates in-place without deleting a legacy deployment directory or making safety bundles.
- [`tasks/compfuzor/vars_src.tasks`](/tasks/compfuzor/vars_src.tasks), [`tasks/compfuzor/fs_repo.tasks`](/tasks/compfuzor/fs_repo.tasks), and [`vars/common.yaml`](/vars/common.yaml) establish the source path and downstream symlink contracts.
- [`tasks/compfuzor/vars_repo.tasks`](/tasks/compfuzor/vars_repo.tasks) formerly removed symlinks ahead of repository update; in archive mode it must not run before the jj snapshot.
