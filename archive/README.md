# archive — a jj toolkit for source archives

Our canonical source archives live at `~/archive/<org>/<repo>`. `dl` is the
primary user of that convention today; compfuzor's `ARCHIVE_DOWNLOAD` lane is
leaning into it rather than making deployment-local clones. This toolkit gives
operators small, individually runnable jj operations as well as a composed
`refresh` for compfuzor. It operates on **the archive's main worktree**; a
deployment-specific jj workspace is a separate, future design. Do not run it
concurrently with another writer to the same checkout.

Run the source directly from a compfuzor checkout (Node type stripping; no
build required):

```sh
node archive/src/repo-jj-archive.ts --help
node archive/src/repo-jj-archive.ts refresh --help
node archive/src/repo-jj-archive.ts complete bash  # also zsh, fish, powershell
```

## Commands

Each command has `--help` with its flags. `--dest` is a jj-colocated checkout
unless the command explicitly creates or detects one.

| Command | Purpose / notable flags |
|---|---|
| `health --dest DIR` | Materialize `visible_heads()` and report conflicted bookmarks before walking history. No mutations. |
| `snapshot --dest DIR` | `jj status`: import colocated Git refs and snapshot tracked/untracked files. |
| `harvest --dest DIR --label NAME [--kind TYPE] [--target REV] [--copy]` | Give a revision a unique `harvest/<label>/…` recovery bookmark. `--copy` duplicates mutable `@` under a different change ID first. |
| `remotes --dest DIR --repo URL [--remotes JSON] [--reconcile]` | Compare declared origin/additional URLs to actual. Differences fail with a table and exact reconcile command; **only** `--reconcile` adds/sets URLs. |
| `fetch --dest DIR --label NAME [--remote NAME]` | Snapshot, harvest dirty `@` if needed, freeze tracked local bookmarks, fetch that remote without abandoning unreachable commits. Does **not** move local base or reconcile `@`; run `refresh` afterward if desired. |
| `refresh --dest DIR --repo URL --label NAME [options]` | Compose adoption/clone, health, snapshot, remote policy, recovery harvest, fetch, base bookmark move, and worktree reconciliation. `--branch HEAD\|branch\|branch@remote`, `--remote NAME`, `--remotes JSON`, `--update true\|false`, `--depth N`, `--json`, `--reconcile-remotes`. Submodules are explicitly unsupported. |
| `heal --dest DIR --yes` | Explicitly move `.jj` to a dated `.jj.broken-ghost-*` backup, then `jj git init --colocate` from Git refs. Refuses without `--yes`. |
| `self [--archive-dir PATH] [--freshen]` | Detect the standard `~/archive/rektide/compfuzor` checkout; optionally fetch its `origin` (no checkout reset). Missing checkout is fine. |
| `complete SHELL` | Generate tab completion via `@gunshi/plugin-completion`. |

For example, inspect and fix a mismatched remote deliberately:

```sh
node archive/src/repo-jj-archive.ts health --dest ~/archive/ORG/REPO
node archive/src/repo-jj-archive.ts remotes --dest ~/archive/ORG/REPO \
  --repo https://github.com/ORG/REPO --remotes '{"peer":"https://github.com/PEER/REPO"}'
# If the printed declared/actual table is right, repeat with --reconcile.
```

`refresh --update false` still validates/adopts the checkout and checks remote
URLs; it skips fetch/base reconciliation when the archive has existing refs.
Missing declared remotes are added in `refresh`; **different URLs on existing
remotes always fail** unless explicitly authorized. `refresh --reconcile-remotes`
opts into rewriting mismatches, whereas `remotes --reconcile` is a standalone
operator step. No command pushes, prunes old refs, or resets a dirty tree.

## Compfuzor / Ansible

[`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
calls `script/repo-jj-archive.ts refresh --json` with `--dest GIT_DIR` (fallback
`REPO_DIR`/`DIR`), `--repo REPO`, `--remotes GIT_REMOTES|default({})`,
`--remote GIT_REMOTE|default('origin')`, `--branch GIT_VERSION|default('HEAD')`,
`--label NAME`, `--update GIT_UPDATE`, and optional `GIT_DEPTH` / `GIT_SUBMODULES`.
`GIT_REMOTE_FIX=true` **explicitly opts into** `--reconcile-remotes`; default is
fail-on-mismatch. Review the failure's URL table before setting that variable.

`COMPFUZOR_REPO_JJ_RUNNER` can override the runner path. By default the
playbook uses `playbook_dir/script/repo-jj-archive.ts`, which imports
`archive/src/repo-jj-archive.ts` first (no bundle transport) or the committed
`archive/repo-jj-archive.mjs` when sources are absent. The optional `self`
command **never** influences this path or requires the compfuzor archive
checkout to exist. The old flag-only invocation is still accepted as an alias
for `refresh --json`; old `--version BRANCH` maps to `--branch BRANCH` (Gunshi
reserves `--version` for its CLI version). Prefer the explicit subcommand.

In `--json` mode stdout has **exactly one JSON result line** on success:

```json
{"changed":false,"notices":[]}
```

Bookmark notices contain `kind: "bookmark-created"`, `name`, and full `target`;
other notices have `kind: "notice"` and `message`. The playbook accumulates
them and prints them at play end. Failures emit diagnostics to stderr, not a
partial JSON result; Ansible checks the return code before parsing stdout.

## Safety and repair

Before any `heads(all())` walk, the toolkit materializes `visible_heads()`.
This catches ghost commits left in jj's view when Git maintenance pruned an
object (including bare heads and conflicted-bookmark terms), and reports the
missing commit ID and repair command rather than jj's opaque backend error.
`health` can run this check independently. Resolve conflicted bookmarks first
if necessary; `heal --yes` is a **last-resort**, explicit re-adoption. The
backup stays in the checkout; Git refs/history still present are reimported,
but jj-only view/operation history is absent from the new `.jj`. Ensure Git
refs themselves are healthy before healing. Never run it on a production
archive to test it: use fixtures. See the
[ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md).

The `refresh` ordering preserves the previous safety contract: snapshot before
fetch; duplicate nonempty `@` under a stable recovery bookmark; untrack local
bookmarks before fetching; preserve diverged old base under a harvest bookmark;
then reconcile the local base and checkout without resetting local work. Remote
URL checks happen after the initial snapshot, **before** harvest/fetch or
bookmark rewrites. See [the original archive design](/design/repo-jj-archive/draft0.gpt6sol.md)
and [the toolkit follow-up](/design/repo-jj-archive/draft1.gpt6sol.md).

## Build, checks, tests

```sh
pnpm check             # formatting, lint, tsgo (including the script/ launcher)
pnpm build             # bundling for distribution only; not type-checking
python3 -m pytest --import-mode=importlib -q tests/integration/repo_jj_archive.test.py
```

The root `vite.config.ts` packs `archive/src/repo-jj-archive.ts` into one
committed `archive/repo-jj-archive.mjs` (ESM, node platform, no type emit,
`clean: false`). Rebuild and commit the bundle with source changes. Integration
tests use disposable jj+Git fixtures and local Ansible plays, never production
archives.
