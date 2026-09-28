# Archive toolkit — keep local work recoverable

Compfuzor keeps source checkouts under `~/archive/<org>/<repo>`. The archive
toolkit manages their jj main worktrees and helps preserve local work across
refreshes. It has two jobs:

- **Routine checkout management:** inspect health, snapshot, harvest recovery
  tips, check remotes, fetch and refresh without resetting a dirty tree.
- **Cross-checkout Git custody:** plan the transfer of selected local Git history
  and worktree content from an older checkout into an **existing** archive,
  install named pins and a receipt, and verify the transfer later.

These are local operations, not remote backup, deployment migration or
permission to delete an old checkout. Do not run them alongside another writer
to either selected checkout. The toolkit operates on the archive's main
worktree, not a deployment-specific jj workspace.

## Start using it

Use Node **26 or newer**, Git and jj. For a copied distribution, run the
committed executable [`archive/repo-jj-archive.ts`](/archive/repo-jj-archive.ts):
it is one file with its JavaScript dependencies bundled, but does **not**
include Node, Git or jj. From a compfuzor checkout with CLI dependencies
installed (`pnpm install`), develop against the TypeScript source instead:

```sh
node archive/src/repo-jj-archive.ts --help
node archive/src/repo-jj-archive.ts refresh --help
```

For example, inspect an archive, then refresh it deliberately:

```sh
node archive/src/repo-jj-archive.ts health --dest ~/archive/ORG/REPO
node archive/src/repo-jj-archive.ts refresh --dest ~/archive/ORG/REPO \
  --repo https://github.com/ORG/REPO --label REPO --branch main
```

`refresh` **mutates** the selected checkout, even with `--update false`:
it can adopt or create a checkout, snapshot/import refs and manage declared
remotes. Inspect its options and select the destination before running it.
A remote URL mismatch fails with the declared/actual table; only
`--reconcile-remotes` authorizes replacing an existing URL. To inspect a
remote policy without refreshing, use `remotes` without `--reconcile`.

For an older checkout with local Git work worth keeping, start with a plan,
not an apply:

```sh
node archive/src/repo-jj-archive.ts adopt \
  --legacy /path/to/old-checkout --dest ~/archive/ORG/REPO \
  --repo https://github.com/ORG/REPO --label REPO --branch main \
  --generation g0 --json
```

Choose an **existing jj-colocated** destination. `adopt` never creates it.
A separate `refresh` can do so, but is itself a mutating checkout operation.
See the [custody guide](/doc/archive-toolkit/custody.md#plan-review-apply-verify)
for review-file examples before using `--apply`.

## Choose a workflow

| Need | Use | Expect |
|---|---|---|
| Check a checkout without changing jj state | `health --dest DIR` | Read-only pinned jj health query and conflicted-bookmark report. |
| Maintain the archive checkout | `snapshot`, `remotes`, `fetch`, or `refresh` | Individually controlled steps or a composed refresh; these can mutate the checkout. |
| Preserve work from an older checkout | `adopt` plan, review, then `adopt --apply` | Existing-destination local Git custody, not a checkout merge or source deletion. |
| Check a prior transfer | `verify-adoption --dest DIR --receipt REF` | Source-independent receipt/pin/vault verification; optional `--legacy` adds drift diagnostics. |

`fetch` snapshots, harvests dirty `@` when needed, freezes tracked local
bookmarks, then fetches. It **does not** converge the archive's base bookmark
or checkout; use `refresh` if you want reconciliation afterward. `health`
uses jj's pinned read-only query mode (`--ignore-working-copy` and `--at-op=@`),
so it does not snapshot or re-import the checkout.

## Read an adoption plan

A plan is an **observation, proposal and admission decision**, not a saved
instruction to execute. Its `source` inventory describes what was actually
inspected; `proposedSnapshot` describes a dirty worktree's candidate tree;
`blockers`, `warnings` and `retirementUnresolved` keep different concerns
separate. For an uninspectable category, `null` means **unknown**, never
"observed empty". An observed empty list is `[]`.

Read `state` and `blockers`, not just the process exit code. A valid read-only
plan with `state: "blocked"` is a useful successful result: fix or investigate
the named issue; do not run apply. `state: "ready"` only admits the reviewed
transfer. It does **not** mean the work has already been preserved, nor that
the old checkout can be retired.

Inspect `source.candidates`, the included/excluded/ignored paths, the HEAD
manifest and any `proposedSnapshot` manifest before deciding what to keep.
Some histories need explicit `--dispositions` keyed by candidate kind and full
OID. Sensitive included paths, or loss of the staged/unstaged distinction,
need an exact `--path-review` bound to the plan's manifest digest. Reviews
approve **local custody**, not publication; they cannot recover an omitted
index-only version. The [guide's review inputs](/doc/archive-toolkit/custody.md#review-inputs)
give the exact JSON shapes and digest locations.

There is no lock, plan file to replay, or implicit approval. `--apply`
**replans**, requires a ready plan and checks source and destination for drift
before installing custody. Keep both checkouts quiescent from plan through
apply; these checks are not an atomic snapshot of a live repository. Changed
inputs require a new plan and review.

## After apply: receipt and verification

Once admitted, `adopt --apply` stages the selected work privately, seals a
bundle in a sibling vault, imports Git objects, installs immutable pin refs and
a receipt under `refs/adopt/receipts/<label>/<generation>`, then verifies.
Apply does not edit either worktree, publish a ref or retire the source.

The receipt records **what the transfer intended and expected**, including
source tips, exact manifests, reviews, pin names and a bundle checksum. A
receipt alone is not proof that the destination still has those objects. Run
the independent verifier using the full receipt ref returned by apply:

```sh
node archive/src/repo-jj-archive.ts verify-adoption \
  --dest ~/archive/ORG/REPO --receipt refs/adopt/receipts/REPO/g0 --json
```

`verify-adoption` checks destination pins, object closure, exact manifests,
the bundle checksum and a fresh restore **without needing the source**.
Optionally pass `--legacy /path/to/old-checkout` to diagnose source drift.
Source and destination drift and `retirementUnresolved` are reported separately
from historical `custodyVerified`; neither a receipt nor a true custody result
authorizes deletion. The private bundle is under `.compfuzor-adoptions/`
**beside** the destination, not inside its worktree or on a remote. Move the
archive and its sibling vault together; a clone without the vault cannot pass
the independent restore proof. Protect the vault's owner-only permissions.

## Limitations and supported scope

**Custody currently requires Linux with usable procfs**. For custody path
reads, the verifier opens directories through anchored `/proc/self/fd`
descriptors and uses `O_NOFOLLOW` to avoid symlink/path-swap check/open races;
the private vault additionally enforces effective-UID ownership and owner-only
file/directory modes. This is a property of this custody implementation, not
a fundamental requirement of Git, jj or Effect. It does **not** imply every
routine checkout command intrinsically needs Linux, nor claim that those
commands have been tested cross-platform.

Custody presently supports an **existing**, healthy jj-colocated destination,
quiesced paths, and commit/tag-tip Git custody. It refuses unsupported source
variants (for example linked worktrees, alternates, shallow or incomplete
object closure, gitlinks/submodules, executable Git helpers and unsupported
filters/LFS). A staged-index-only version without a synthetic snapshot is
blocked; an approved dirty snapshot retains one resulting worktree tree, not
separate index and unstaged versions. Consult the
[admission boundary](/doc/archive-toolkit/custody.md#admission-boundary)
for the full gate and left-behind categories.

Ignored runtime files, explicitly excluded untracked paths, Git/jj internals
and jj operation history are not preserved by Git custody. Local
remote-tracking refs are only a recorded baseline, not proof of server
freshness. This toolkit does not automatically push, prune old artifacts,
delete a source, or select/deploy a workspace. Plan and verification reports
can still contain independently unresolved retirement work.

## Command reference

Each command accepts `--help`. `--dest` denotes a jj-colocated checkout unless
the command explicitly creates or detects one.

| Purpose | Command and notable options |
|---|---|
| Inspect | `health --dest DIR` checks visible jj heads and conflicted bookmarks without mutation. `remotes --dest DIR --repo URL [--remotes JSON]` compares URLs; only `--reconcile` adds/sets them. |
| Maintain | `snapshot --dest DIR` runs jj status/import. `fetch --dest DIR --label NAME [--remote NAME]` freezes local bookmarks before fetching without reconciling the checkout. `refresh --dest DIR --repo URL --label NAME [--branch HEAD\|branch\|branch@remote] [--remote NAME] [--remotes JSON] [--update true\|false] [--depth N] [--json] [--reconcile-remotes]` composes checkout maintenance; submodules are unsupported. |
| Recover | `harvest --dest DIR --label NAME [--kind TYPE] [--target REV] [--copy]` creates a unique recovery bookmark. `heal --dest DIR --yes` backs up `.jj` and re-adopts from Git refs; use **only as an explicit last resort** after confirming Git refs are healthy. jj-only view/operation history will not survive the new `.jj`. |
| Custody | `adopt --legacy DIR --dest DIR --repo URL --label NAME [--branch BRANCH] [--generation ID] [--exclude-from FILE] [--dispositions FILE] [--path-review FILE] [--json] [--apply]` plans by default; `--apply` transfers. `verify-adoption --dest DIR --receipt refs/adopt/receipts/NAME/ID [--legacy DIR] [--json]` checks installed custody. |
| Toolkit | `self [--archive-dir PATH] [--freshen]` detects the canonical compfuzor checkout; freshening fetches its origin only. `complete SHELL` prints completions for bash, zsh, fish or PowerShell. PowerShell covers only subcommand names and global flags; POSIX shells get the command flag tree. |

`health` detects missing jj-visible Git objects before broader head walks. If
jj reports ghost heads, diagnose the [incident and repair context](/design/repo-jj-archive/incident-ghost-heads.glm53.md)
before considering `heal`. `refresh` snapshots before fetching, harvests local
work, untracks local bookmarks before fetch and preserves a diverged old base;
it does not reset a dirty tree. `--update false` still has mutating checkout
setup and remote checks; on an existing archive with refs, it skips fetch/base
reconciliation. No command pushes or prunes old refs.

## Compfuzor integration

[`tasks/compfuzor/repo_jj_archive.tasks`](/tasks/compfuzor/repo_jj_archive.tasks)
runs `refresh --json` for the declared `GIT_DIR` (fallback `REPO_DIR`/`DIR`),
`REPO`, `GIT_REMOTES`, `GIT_REMOTE`, `GIT_VERSION`, `NAME`, `GIT_UPDATE` and
optional `GIT_DEPTH`/`GIT_SUBMODULES`. A mismatched existing remote URL fails
unless `GIT_REMOTE_FIX=true` explicitly requests reconciliation.

For the runner, the host's canonical compfuzor checkout
(`COMPFUZOR_ARCHIVE`, normally `~/archive/rektide/compfuzor`) is preferred
**when its launcher is executable**. Otherwise the executing playbook's
`script/repo-jj-archive.ts` is used. This remains the fallback even when
another checkout rendered the playbook; runner selection is not an automatic
update of either checkout. Set `COMPFUZOR_REPO_JJ_RUNNER` to choose a specific
runner. `COMPFUZOR_SELF_FRESHEN=true` opts into fetching the host checkout's
origin before selection, without resetting its worktree.

The launcher runs source when source and installed Effect CLI dependencies are
available, otherwise the committed single-file bundle. In `--json` mode a
successful refresh writes exactly one result line, for example
`{"changed":false,"notices":[]}`. Failures write diagnostics to stderr and no
partial JSON line; the task checks the exit code before parsing stdout. The
older flag-only invocation remains an alias for `refresh --json`, including
its `--version BRANCH` spelling; prefer the explicit subcommand.

## Architecture and development

The source groups CLI parsing and commands under `archive/src/cli/`, ordinary
checkout work under `repository/`, jj repair under `recovery/`, and local Git
custody under `custody/`. The CLI uses Effect (`effect` and
`@effect/platform-node`, pinned at 4.0.0-rc.118). Repository/recovery library
helpers return Promises; custody planning/apply return Effects. See the
[public library entry points](/doc/archive-toolkit/custody.md#public-library-entry-points).

`pnpm build` creates the committed `archive/repo-jj-archive.ts` for **distribution
only** (ESM, Node 26, bundled JavaScript dependencies, no Node binary). Run
source during development and rebuild/commit the bundle when source changes.
Useful checks:

```sh
pnpm check
pnpm build
node --test 'archive/test/**/*.test.ts'
python3 -m pytest --import-mode=importlib -q tests/integration/repo_jj_archive.test.py
```

Local fixture [distribution verification](/design/archive-toolkit/verification0.gpt6luna.md)
passed 127 Node tests, 34 integration tests and reproducible bundle builds.
The [focused custody safety disposition](/design/archive-toolkit/safety-review0.gpt6sol.md#final-focused-checkpoint-standalone-verifier-helper-gate)
found no remaining blocker **within its Linux, quiesced-path,
existing-destination, commit/tag-tip scope**; it is not production or source
retirement approval. For the design lineage, see the
[original archive design](/design/repo-jj-archive/draft0.gpt6sol.md) and
[custody guide](/doc/archive-toolkit/custody.md).
