# archive — a jj toolkit for source archives

Our canonical source archives live at `~/archive/<org>/<repo>`. `dl` is the
primary user of that convention today; compfuzor's `ARCHIVE_DOWNLOAD` lane is
leaning into it rather than making deployment-local clones. This toolkit gives
operators small, individually runnable jj operations as well as a composed
`refresh` for compfuzor. It operates on **the archive's main worktree**; a
deployment-specific jj workspace is a separate, future design. Do not run it
concurrently with another writer to the same checkout.

The CLI is built on Effect (`effect` and `@effect/platform-node`, pinned at
4.0.0-rc.118); the operations library underneath stays Promise-based, with
Effect adopted at the CLI boundary. Run the source directly from a compfuzor
checkout (Node type stripping; no build required — source development needs
the CLI dependencies installed via `pnpm install`):

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
| `health --dest DIR` | Materialize `visible_heads()` and report conflicted bookmarks. Runs in the pinned read-only query mode (`--ignore-working-copy` + `--at-op=@`): the checkout's jj state is observed, never snapshotted or re-imported. |
| `snapshot --dest DIR` | `jj status`: import colocated Git refs and snapshot tracked/untracked files. |
| `harvest --dest DIR --label NAME [--kind TYPE] [--target REV] [--copy]` | Give a revision a unique `harvest/<label>/…` recovery bookmark. `--copy` duplicates mutable `@` under a different change ID first. |
| `remotes --dest DIR --repo URL [--remotes JSON] [--reconcile]` | Compare declared origin/additional URLs to actual. Differences fail with a table and exact reconcile command; **only** `--reconcile` adds/sets URLs. |
| `fetch --dest DIR --label NAME [--remote NAME]` | Snapshot, harvest dirty `@` if needed, freeze tracked local bookmarks, fetch that remote without abandoning unreachable commits. Does **not** move local base or reconcile `@`; run `refresh` afterward if desired. |
| `refresh --dest DIR --repo URL --label NAME [options]` | Compose adoption/clone, health, snapshot, remote policy, recovery harvest, fetch, base bookmark move, and worktree reconciliation. `--branch HEAD\|branch\|branch@remote`, `--remote NAME`, `--remotes JSON`, `--update true\|false`, `--depth N`, `--json`, `--reconcile-remotes`. Submodules are explicitly unsupported. |
| `heal --dest DIR --yes` | Explicitly move `.jj` to a dated `.jj.broken-ghost-*` backup, then `jj git init --colocate` from Git refs. Refuses without `--yes`. |
| `self [--archive-dir PATH] [--freshen]` | Detect the standard `~/archive/rektide/compfuzor` checkout; optionally fetch its `origin` (no checkout reset). Missing checkout is fine. |
| `adopt --legacy DIR --dest DIR --repo URL --label NAME [--branch BRANCH] [--generation ID] [--exclude-from FILE] [--dispositions FILE] [--path-review FILE] [--json] [--apply]` | Plan local Git custody without writes by default; `--apply` explicitly installs pins, a receipt and private vault bundle, then verifies. Requires an **existing** destination. |
| `verify-adoption --dest DIR --receipt refs/adopt/receipts/NAME/ID [--legacy DIR] [--json]` | Independently verify receipt, pins and vault without requiring the source; optional `--legacy` adds drift diagnostics. |
| `complete SHELL` | Print a tab-completion script. `bash`/`zsh`/`fish` come from Effect CLI's command-tree generator (byte-identical to the native `--completions` action); `powershell` comes from a static generator covering **only subcommand names and global flags** — not the per-command flag tree the POSIX shells get. |

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

Runner resolution is a **dual path**: the host's canonical compfuzor checkout
(`COMPFUZOR_ARCHIVE`, `~/archive/rektide/compfuzor` per
[`vars/common.yaml`](/vars/common.yaml)) is preferred when its
`script/repo-jj-archive.ts` launcher exists, so archive refreshes run the
freshest toolkit regardless of which checkout renders the playbook. When that
checkout is absent, the executing playbook's own
`playbook_dir/script/repo-jj-archive.ts` is the fallback that always works.
`COMPFUZOR_REPO_JJ_RUNNER` overrides both — the escape hatch when the host
checkout is stale or broken. Both entries go through the same launcher
contract, which imports `archive/src/repo-jj-archive.ts` first when the source
**and the installed CLI dependencies** (`node_modules/effect` and
`node_modules/@effect/platform-node`) are present (no bundle transport), or
the committed single-file bundle `archive/repo-jj-archive.ts` (erased JS
emitted as TypeScript, runs on system Node ≥ 26) when either is absent.
The launcher calls the entry's `runExecutable()` so Node's native signal
handling tears down active child processes; `main()` remains an importable
Promise API. Direct execution of the source entry or copied bundle uses the
same `runExecutable()` path.
`COMPFUZOR_SELF_FRESHEN=true` opts into fetching the host checkout's origin
before resolution (fetch only, never a worktree reset; a missing checkout is
a clean no-op). A run resolved to the host checkout says so with a
`host compfuzor checkout preferred` debug line. The old flag-only invocation
is still accepted as an alias for `refresh --json`; in that spelling (and
under an explicit `refresh`) the old `--version BRANCH` maps to `--branch
BRANCH`, while root `--version` on its own prints the toolkit version.
Prefer the explicit subcommand.

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

## Custody: available for fixture evaluation; safety review in progress

Cross-repository source custody is exposed by `adopt` (read-only planning by
default; `--apply` explicitly transfers and verifies custody) and
`verify-adoption` (independent receipt/pin/vault verification). These commands
have passed local clean/dirty existing-destination fixtures, but independent
safety review remains open: **not production signoff** or a complete
implementation of the [custody brief](/design/archive-migration/brief0.gpt6sol.md).
Use [the custody operator and library guide](/doc/archive-toolkit/custody.md)
for admission limits, review-file formats, plan/apply/verify examples, and
what a receipt actually proves. In particular, adoption never creates a
destination; a separate `refresh` may initialize one deliberately, but also
mutates the selected checkout. Custody operations do not publish refs, prune
artifacts, or retire a source directory; verification never grants deletion
permission. See the [core review](/design/archive-toolkit/core-review0.glm53.md)
and [custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md).

## Build, checks, tests

```sh
pnpm check             # formatting, lint, tsgo (including the script/ launcher)
pnpm build             # bundling for distribution only; not type-checking
node --test archive/test/repository/cancellation.test.ts # real source/launcher/bundle signal paths
python3 -m pytest --import-mode=importlib -q tests/integration/repo_jj_archive.test.py
```

The source is grouped by domain: `archive/src/cli/` (command tree, flags,
legacy argv adapter, completions), `repository/` (ordinary checkout
operations, including the `jj`/`git` execution boundaries — subprocesses run
as argv arrays through Effect's `ChildProcessSpawner`, never a shell),
`recovery/` (jj recovery and explicit repair), and `custody/` (registered,
under safety review). Adding a command is a new module under `cli/commands/`
plus one registry entry.

The root `vite.config.ts` packs `archive/src/repo-jj-archive.ts` into one
committed `archive/repo-jj-archive.ts` (ESM, Node platform, `node26`, no type
emit, code splitting, or source map). Rolldown's erased JavaScript is valid
TypeScript, so Node 26 executes this single file with native type stripping.
The bundle includes all JavaScript dependencies and has only `node:` imports;
it contains no Node runtime. The host supplies system Node 26 from the
Nodesource 26.x package declared by [`nodesource.repo.pb`](/nodesource.repo.pb).
There is no compatibility target for older Node versions. This is
**distribution only** — the file runs outside this checkout without
`node_modules`; develop against the source instead. Rebuild and commit the
bundle with source changes. While source changes are still landing the
committed bundle may lag behind; run `pnpm build` and commit the result before
relying on bundle freshness. Integration tests use disposable jj+Git fixtures
and local Ansible plays, never production archives.
