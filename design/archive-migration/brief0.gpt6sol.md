---
type: ImplementationBrief
title: Archive adoption — Git custody implementation brief
description: Executable admission, inventory, isolated import, immutable receipt and verification contract for adopting a standalone Git checkout without deploying or retiring it.
resource: /design/archive-migration/brief0.gpt6sol.md
tags: [compfuzor, archive, adoption, git, jj, custody]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: authoritative-design
    resource: /design/archive-migration/draft0-syn2.gpt6sol.md
    title: Receipt-driven source custody design
  - id: fixture-analysis
    resource: /design/archive-migration/draft0.gpt6sol.md
    title: Fixture-tested hazards and manual walkthrough
  - id: existing-toolkit
    resource: /archive/README.md
    title: Archive toolkit and CLI contract
  - id: legacy-transport
    resource: /script/deprecated-harvest-legacy-repo.sh
    title: Deprecated cross-checkout transport
---

# Archive adoption: implement Git custody, not a migration of the running application

## Situation, outcome, permissions

[`draft0-syn2.gpt6sol.md`](/design/archive-migration/draft0-syn2.gpt6sol.md)
is the governing design. A standalone checkout may hold history absent from the
archive: `dl`'s detached HEAD had **374 commits not reachable from its locally
recorded `github/main`** at inspection, not necessarily 374 commits absent from
every server. Its old harvest also swept `.jj/`, omitted the synthetic commit
from its pre-import bundles, and rewrote a recovery ref on retry. This brief
specifies a replacement that can say *exactly which Git objects and named tips
it took custody of*, and prove that claim after the source disappears.

The v1 boundary is: `adopt` defaults to a read-only plan; `adopt --apply`
creates a private, self-contained Git bundle and adds **only immutable archive
custody refs/objects and a receipt ref**; top-level `verify-adoption` checks
those artifacts and reports remaining retirement preflight items. Neither
command changes the legacy repository (including its object database or jj
state), existing destination refs, destination worktree, remotes, or deployment
selection. No fetch of the source or an existing archive (an explicitly
declared first clone of an absent archive is the only network acquisition),
publish/push, runtime-state backup or restoration,
Ansible, shim relink, cleanup, disposal, or workspace choice is part of v1.
External writers must be stopped; fingerprint checks detect many races, but
cannot create an atomic cross-filesystem snapshot of a live checkout.

## Admission and disposition

`plan` always returns a *complete inventory where inspection is possible*;
`--apply` requires no Git-custody blockers or unclassified candidate work.
An explicit disposition is recorded in the plan and receipt, never silently
inferred from a missing ref or an ignored file. `--dispositions FILE` accepts
JSON decisions keyed by candidate kind and full OID: `pin` or `not-required`,
the latter with an operator reason; its SHA-256 and each decision belong in
the receipt. Known refs and stash/reflog tips default to `pin`; dangling
commit/tag candidates require classification. A selected reflog candidate's
stable pin identity is kind + full OID, with every matching reflog entry
retained as provenance. Unreferenced noncommit objects are inventoried but
not mistaken for wanted revisions. “Operator action” means work outside this
command followed by a fresh plan, or this explicit classification; it never
means a force option.

| Legacy condition | v1 disposition |
|---|---|
| Ordinary complete Git checkout; clean branch HEAD | Admit; pin all selected refs plus HEAD, even if HEAD is already reachable. |
| Detached HEAD (including ahead/diverged from a recorded remote tip) | Admit; separately pin exact commit. State baseline URL/ref/OID and count against that OID; never call the count “unpushed” without independently validated remote authority. |
| Dirty tracked/index, untracked, deletions | Admit only after exact manifest and privacy review; synthesize one worktree tree/commit without mutating source. Report staged versus unstaged separately: one resulting tree **does not preserve two separate states**. If that distinction must be recoverable, stop for explicit extra index custody/design rather than claim it was saved. Unmerged index entries block. |
| Ignored DBs, caches, `.jj`/`.git` metadata | Never put untracked internals or ignored files into the synthetic tree; inventory paths as **left behind**, not contents. Ignored runtime state is a retirement unresolved item, not a failure to preserve declared Git work. Tracked matching paths cannot be excluded: keep in history/tree and flag privacy risk; unexplained included private/transient paths block until classified. |
| Git branches and lightweight/annotated tags | Admit with typed, exact-OID mapping; preserve annotated **tag objects**. A tag target is not a branch target. |
| `refs/stash`, every stash reflog entry, notes, replace and other refs | Inventory and admit if their object types/closures can be validated and mapped to the generic custody lane. Older stash entries and reflog-only wanted commits require **new private pins**; disposition each candidate as selected or explicitly not required. Unclassified candidate = apply blocker. Do not equate a `--all` bundle with reflog custody. |
| Valid jj-colocated source | Read-only inventory of jj visible heads, conflicts, Git-export coverage and jj-only revisions. Admit only when coverage of *every wanted jj head* by selected Git tips is proven; otherwise block for separately authorized export/pin and re-plan. Never invoke `jj status` or `jj git export` on source. Failed jj inspection = blocker, not proof of absence. An inert `.jj` placeholder must be classified as invalid metadata and left behind, never captured as source files. |
| Unborn HEAD, bare/alternate worktree (`.git` file), shallow/partial/promisor clone, sparse checkout, alternates, submodules, LFS/smudging or active filters whose bytes cannot be faithfully staged | Block v1; report the specific unsupported invariant and request operator preparation/re-plan. Do not fetch missing objects implicitly or promise LFS payload custody from pointers. Symlinks stay symlinks (no target traversal); reject paths that resolve outside the proposed root during input acquisition. |
| Corrupt/missing selected objects or missing reachable parents, conflicted destination jj view/bookmarks, busy destination checkout, declared destination URL mismatch | Block before destination writes. Existing archive must pass [`preflight()`](/archive/src/health.ts) **with no conflicts** plus Git object/ref and worktree checks; never auto-heal, snapshot, reconcile or reset. |

Source `.git` may be a directory only for admitted v1 source; use Git's
`--absolute-git-dir`/`--git-common-dir` inspection to *detect* linked worktrees
and reject safely. Canonicalize source/destination, reject identical, nested,
symlink-aliased or occupied non-repository destinations. Missing destination:
plan describes creation, with no mutation; apply may create a full
jj-colocated clone using the existing `refresh` clone path **only after
inventory and preflight**, with `--update false`, no depth, and explicitly
recheck state. Do not call `refresh` on an existing archive: its `jj status`
snapshots and imports refs even with `--update false`
([`refresh.ts`](/archive/src/refresh.ts)). If clean creation cannot be
guaranteed without affecting an existing checkout, stop instead.

## Read-only inventory and guarantee set

Inventory runs `git` plumbing with argument arrays, explicit cwd/Git dir,
`GIT_OPTIONAL_LOCKS=0` and maintenance disabled for source-side inspection;
never invoke a command that stages, commits, exports, repairs or fetches in
the source. Record raw full refnames and OIDs (`for-each-ref`, not abbreviated
names), symbolic/detached HEAD and commit/tree, tags and peeled targets, stash
ref and **all** stash/reflog tips (`reflog show --all`), notes/replace/custom
refs, and `fsck --no-reflogs --unreachable` candidate commits/objects without
`--lost-found`. A dangling object is a *candidate*, not automatically user
work: classify wanted candidates or explicitly record exclusion with reason.
Only an explicitly enumerated selected set becomes a custody promise.

Inventory index stages, staged/unstaged/deleted modes and OIDs; enumerate
tracked, untracked-with-ignore-rules and ignored paths using NUL-delimited Git
output so filenames cannot spoof delimiters. Capture original index byte hash
and source `HEAD`/ref map, and make a proposed *included* path/mode/blob-OID
manifest for the exact synthetic tree. Deny `.git` and `.jj` path components
irrespective of ignore rules; `--exclude-from FILE` and normal ignores select
only **untracked** input, and their file hash/policy are recorded. Name
tracked key/credential-class and runtime-like paths (including `.beads` and
`.data`), ignored state paths, excluded paths and the reason for each; show
names/classes, **never file contents or credential values**. Check source
remotes as URL/name plus recorded remote-tracking ref and tip; no fetch in
plan/apply. Inspect destination ref namespace, worktree status and declared
`--repo` versus actual `origin` (legacy `origin` can be Tangled while archive
`origin` is GitHub). Baseline reporting includes exact source HEAD, locally
recorded baseline tip and URL, destination pre-import protected tips, and
deduplicated commit counts for each named comparison. Unknown/stale/partial
baselines yield `unknown`, never zero or “unpushed”. Report consumer/backup
evidence only as observed/unverified preflight items, not deployment decisions.

**Provable guarantees:** a fully applied receipt establishes named Git tip
OIDs, commit/tree and blob path manifest, and a fresh-repository-restorable
bundle of their complete Git closure. It does **not** establish preservation
of ignored files, live DB consistency, jj operation history, LFS payloads,
independent/off-host backup, remote publication, or a runnable deployment.
This distinction belongs in every plan and verification report.

**Source ODB hazard:** the prior [isolated fixture probe](/design/archive-migration/draft0-syn2.gpt6sol.md#what-the-evidence-actually-says)
ran `git add` with `GIT_INDEX_FILE` pointed elsewhere; the original index and
worktree stayed unchanged, but the source ODB gained the untracked file's
blob. `GIT_INDEX_FILE` by itself is **not** a read-only-source mechanism.
For both plan-tree calculation and apply, use a Git repository/index/object
directory in private scratch **outside both checkouts**, with read-only access
to source Git objects via alternates. Set `GIT_DIR`, `GIT_WORK_TREE`,
`GIT_INDEX_FILE` and `GIT_OBJECT_DIRECTORY` to staging locations; source
objects may be read, never chosen as the write destination. Disable or block
external clean/smudge filters until their behavior is proven. Check source
ODB/index/config/refs/reflogs and worktree fingerprints before and after
staging; test object counts **and** on-disk object listings (packs included).

## CLI and file ownership

```text
node archive/src/repo-jj-archive.ts adopt --legacy DIR --dest DIR \
  --repo URL --branch main --label NAME [--generation g0] \
  [--exclude-from FILE] [--dispositions FILE] [--json]  # plan (default)
node archive/src/repo-jj-archive.ts adopt <same options> --apply [--json]
node archive/src/repo-jj-archive.ts verify-adoption --dest DIR \
  --receipt refs/adopt/receipts/NAME/g0 [--legacy DIR] [--json]
```

`--generation` defaults to literal `g0`; a changed source tip under an
occupied generation **requires the operator to choose a fresh generation**
or label (no automatic time-based fallback). Validate label/generation exactly
as ref components, fail instead of lossy normalization (the existing
[`harvest.ts`](/archive/src/harvest.ts) `safeLabel` is not safe for injective
custody mapping). Reject a reserved/prefix-conflicting existing namespace,
not just an identical leaf ref. HEAD and worktree use content-addressed leaf
names; generation still scopes them consistently with branches.

Place read-only Git discovery, policy and fingerprints in new
`archive/src/adopt-inventory.ts`; private Git stage, bundle and ref transaction
in `archive/src/adopt.ts`; receipt schema, encoding, durable read/write and
verifier in `archive/src/adopt-receipt.ts` (a separate verifier module is fine
if it stays focused). Share the existing `health.ts` jj preflight and
`remotes.ts` declared-URL comparison as *read-only checks*; do **not** extend
the jj-internal `harvest.ts` or routine `refresh.ts` with cross-repository
transport. Register **two top-level Gunshi commands** in
[`archive/src/repo-jj-archive.ts`](/archive/src/repo-jj-archive.ts); keep
[`script/repo-jj-archive.ts`](/script/repo-jj-archive.ts) unchanged. For
`--json`, successful plan/apply/verification each emits exactly **one** JSON
object line on stdout, no progress chatter; validation/apply/verification
failure is nonzero with diagnostic on stderr and no partial JSON. A *valid*
plan may contain `blockers`/`warnings` without being an execution failure;
apply refuses them. Successful verification can still carry unresolved
**retirement** items; `custodyVerified` is separate from retirement readiness.

## Receipt, durable location and interrupted runs

The canonical receipt is a UTF-8 `adoption.json` Git blob in a small metadata
commit (fixed metadata and no parent) pinned at
`refs/adopt/receipts/<label>/<generation>` **inside the destination Git ODB**.
Never check it out or add it to the archive's main branch/worktree; protect the
receipt ref with the same compare-and-create immutability rule as recovery
refs. Do not embed its own commit OID in its JSON (self-reference); the
verifier reads and reports the observed receipt commit OID. Example *shape*,
with arrays shown schematically:

```json
{
  "schema": "compfuzor.archive-adoption/v1",
  "receiptRef": "refs/adopt/receipts/dl-legacy/g0",
  "identity": { "label": "dl-legacy", "generation": "g0", "legacyRealpathAtCapture": "/home/user/src/dl", "sourceGitCommonDir": "/home/user/src/dl/.git", "destinationRealpath": "/home/user/archive/org/dl", "createdAt": "2026-09-27T00:00:00Z" },
  "source": { "objectFormat": "sha1|sha256", "head": { "symbolicRef": null, "oid": "<commit-oid>", "treeOid": "<tree-oid>", "treePaths": [{ "path": "README.md", "mode": "100644", "blobOid": "<oid>" }] }, "refs": [{ "name": "refs/heads/main", "oid": "<oid>", "objectType": "commit", "peeledOid": "<oid>" }], "reflogCandidates": [{ "oid": "<oid>", "kind": "stash-older", "disposition": "pinned", "destinationRef": "<ref>" }], "jjCoverage": { "classification": "none|git-covered|blocked", "headOids": [] }, "indexSha256": "<sha256>", "inputFingerprintSha256": "<sha256>", "dispositionsFileSha256": null },
  "snapshot": { "format": "worktree-v1", "parentOid": "<oid>", "treeOid": "<oid>", "commitOid": "<oid>", "paths": [{ "path": "README.md", "mode": "100644", "blobOid": "<oid>" }], "stagedVsUnstaged": "reported-not-preserved", "excludeFileSha256": null, "excludedUntracked": [], "ignoredPaths": [], "trackedSensitivePaths": [] },
  "baselines": { "sourceRemoteTracking": [{ "remote": "github", "url": "<url>", "ref": "refs/remotes/github/main", "oid": "<oid>", "freshness": "local-only" }], "destinationPreRefs": [{ "name": "refs/heads/main", "oid": "<oid>" }], "destinationPreRefsSha256": "<sha256>", "destinationWorktreeFingerprintSha256": "<sha256>", "selectedBranch": "main", "declaredRepo": "<url>", "counts": { "headNotInRecordedBaseline": 374, "selectedTipsNotInDestination": "<integer-or-unknown>" } },
  "pins": [{ "sourceKind": "branch|head|tag|stash|other|reflog|working-copy", "sourceName": "<full-ref-or-candidate-id>", "sourceOid": "<oid>", "objectType": "commit|tag|tree|blob", "destinationRef": "<full-ref>", "destinationOid": "<oid>" }],
  "bundle": { "pathRelativeToDestinationParent": ".compfuzor-adoptions/<archive-id>/<run-id>/source.bundle", "sha256": "<sha256>", "verifiedHeads": [{ "ref": "<stage-ref>", "oid": "<oid>" }], "freshRestoreVerified": true },
  "checks": { "sourceFingerprintRechecked": true, "sourceOdbUnchanged": true, "destinationWorktreeUnchanged": true, "bundleClosureVerified": true },
  "unresolved": [{ "kind": "ignored-runtime-state|consumer|independent-backup|...", "pathOrRef": "<optional>", "reason": "<classification>" }]
}
```

The example's OIDs/placeholders are illustrative, not a migration manifest.
Use full OIDs, full original names, sorted NUL-safe inventories, Git modes and
OID format/hash algorithm; serialize canonically for equality checks (no
path-derived string interpolation in Git commands). Ref/path bytes that cannot
be represented losslessly in the JSON schema must **block v1 admission**
with a named reason, not round-trip through lossy UTF-8 decoding. Hash the
canonical HEAD/ref/reflog selection, index bytes, included path/mode/blob
manifest, exclusion/disposition files and destination declared remote for the
source/input fingerprint. Include the *clean HEAD tree manifest* even if
`snapshot` is null, so verification checks exact paths as well as its OID.
Record exact pre-import destination ref map and worktree/index fingerprint,
not only their hash summaries. Enforce schema validation
and reject unknown incompatible versions. Preserve the exact proposed
snapshot manifest including tracked exceptions; when clean, use
`snapshot: null`. Never record secret values or ignored-file contents in the
receipt; the paths themselves are potentially private, so guard access.

The bundle lives outside both worktrees in a sibling, owner-only vault:
`dirname(dest)/.compfuzor-adoptions/<sha256-of-canonical-dest>/<random-128+-bit-run-id>/source.bundle`;
directories `0700`, files `0600`, atomic write+rename, fsync data and
directory before installing archive refs. Store the signed-off plan/intent
beside it for restart diagnosis; no timestamp-only path and no overwrite of
pre-existing vault files. The receipt records a constrained relative path,
checksum and exact bundle heads; `verify-adoption --dest ... --receipt REF`
reads `REF:adoption.json` from destination Git **without opening the legacy
path** and validates the path stays in its private vault (no symlink/path
escape). A moved archive needs its private vault moved with it; a Git clone
carrying the receipt ref but not the vault correctly fails bundle verification.

Build and verify the complete bundle of **source tips and synthetic commit
first**; only then compute its checksum and construct the metadata receipt
commit in private stage. Do not add that receipt commit to the bundle (its
embedded bundle checksum would form a circular dependency). Before *any*
destination ref write both artifacts must exist; import the objects, atomically create the receipt ref
with expected-old zero, then atomically compare-and-create all new pins (one
`git update-ref --stdin` transaction when possible). This receipt describes
an **expected transfer**, not a success certificate: verification alone
reports completion. If interrupted, existing receipt + immutable bundle
manifest enable a same-input resume of missing refs using expected-old zero;
matching refs are no-ops. Without a matching receipt/intent, even partially
installed refs require inspection, not overwrite, deletion or guesswork.
Precheck the *entire* namespace before staging/bundle work and recheck under
the ref transaction. On a retry with an existing receipt ref, **read that
receipt first**: compare its recorded source input fingerprint and intended
mapping against the new inventory, discounting only its *own* already
installed custody refs from the destination pre-state. Never mint a second
receipt with a new timestamp or reinterpret a changed destination baseline
as a new import of the same generation. Matching receipts/refs are no-ops;
receipt ref collision with different content is a hard stop. Restrict Git
maintenance/pruning from discarding staged-only objects until they are
protected; retained vault and receipt serve restart diagnosis.

## Stage, bundle and typed ref mapping

Build a bare scratch repository outside both checkouts; read source objects
through alternates, with private object directory and temporary index. Read
source HEAD tree into that index, stage tracked modifications/deletions and
only the selected untracked paths from an explicit NUL-safe manifest. Every
`git add`/`write-tree`/`commit-tree` failure is fatal. Validate resulting
tree against the proposed path/mode/blob manifest and forbid `.git`/`.jj`
components even when tracked: if tracked internals exist, block rather than
silently delete them. Mint the working-copy commit *only if tree differs from
HEAD tree*, with HEAD as parent and fixed author/committer/message/timestamps
by `worktree-v1` format. Identical parent+tree+format must produce identical
commit OID; record the tree independently so the verifier does not have to
trust metadata. Re-read source/index/ref and manifest fingerprints before
transfer; abort on drift, never silently capture a newer tree than planned.

Copy all selected source objects into scratch **by reachable closure**, attach
private staging refs to every original selected tip, older stash/reflog pin
and synthetic commit, and create a no-prerequisite `git bundle create ...
--all` *there*, **before** destination import. Verify bundle head names/OIDs,
checksum and `git bundle verify` against an **empty** fresh repository;
unbundle/fetch into that repository and check all pinned objects, commit
parents, tag targets and complete snapshot tree (not merely `bundle verify`
against the populated archive). Source-only objects must remain obtainable
after source removal. A bundle of source `--all` made before `commit-tree`
cannot meet this guarantee.

Map by *source kind*; encode original ref bytes injectively as a
length-prefixed hex path with fixed-size components, validate `git
check-ref-format`, and round-trip it against the receipt. Precheck both
exact-name **and file/directory-prefix** conflicts, including legacy
`harvest/<label>/head`/`working-copy` from the previous script:

| Source value | Destination ref (under `<label>/<generation>`) | Requirement |
|---|---|---|
| Local branch `refs/heads/X` | `refs/heads/harvest/<label>/<generation>/branch/<encode(X)>` | Commit OID only; never move old branch pin. |
| Current HEAD | `refs/heads/harvest/<label>/<generation>/head/<HEAD-oid>` | Commit OID, including detached HEAD. |
| Dirty synthetic tree | `refs/heads/harvest/<label>/<generation>/working-copy/<parent>-<tree>-worktree-v1` | Commit OID; unchanged retry has identical name **and** OID. |
| `refs/tags/X` | `refs/tags/harvest/<label>/<generation>/<encode(X)>` | Keep exact tag OID (annotated **tag object**, lightweight target OID); never put tag object in `refs/heads/`. |
| Stash, notes, replace, nonstandard ref, selected reflog-only tip | `refs/adopt/custody/<label>/<generation>/<kind>/<encode(full-name-or-stable-candidate-id)>` | Keep object type/OID and provenance in receipt; stash older entries get separate pins. No source `refs/replace` activation in destination. |

Preserve all included source refs or record an explicit unresolved exclusion;
don't treat tag/stash candidates as branches or say a bundle alone substitutes
for a promised pin. Namespace is append-only: same label+generation+snapshot
maps to identical refs/receipt and is a verified no-op; changed branch OID
under an occupied generation blocks and asks for a **new generation**. New
generation preserves every old ref and receipt. Import Git objects without
checking out or moving `main`, then install refs compare-and-create; do not
`git push +`, run `jj status`/`jj git import` as a source mutation, or depend
on jj bookmarks alone to protect custom refs. Check jj visibility and archive
worktree equality after transfer; `health` is additional evidence, not the
custody proof.

## `verify-adoption`: source-independent custody and retirement preflight

The verifier locates the receipt by **full ref** in `--dest`, checks ref object
type and schema, reconstructs and validates expected mappings, reads *each*
archive ref with exact expected OID/object type, tests Git object closure and
path/mode/blob snapshot tree, and checks bundle checksum, advertised heads
and restoration in a fresh empty repository. Check jj visible heads and
conflicts, plus archive worktree unchanged from receipt's pre-state if the
destination has not since undergone an explicitly separate change; report
subsequent destination drift separately, not as proof that archived historical
tips disappeared. Verifier must work when `--legacy` is omitted and the old
path no longer exists. With `--legacy`, compare HEAD/ref/index/worktree
fingerprints and jj coverage with those captured: source drift is diagnostic,
not retroactive loss of already verified Git custody.

Return distinct `custodyVerified`, `sourceDrift`/`unknown`, and
`retirementUnresolved[]` statuses. Even perfect Git custody leaves ignored
DB/WAL state, jj op log, tracked-credential publication review,
source-path consumers/shim targets, LFS/submodule coverage and independent
backup evidence as unresolved or not independently checked. The command
offers **no “safe to delete” verdict** and has no deletion/retirement
execution. Failed receipt/bundle/ref checks are custody failures; do not
hide them inside an otherwise reassuring retirement report.

## Verification slices and acceptance fixtures

Implement the **receipt parser/verifier and isolated-bundle proof together**
before claiming apply success. Suggested coherent slices (commit each):

1. Inventory/admission + JSON plan, using synthetic Git fixtures; prove the
   source ODB/index/worktree/jj store is unchanged and that blockers, baseline
   counts and left-behind items are reported accurately.
2. Private stage, deterministic snapshot, complete bundle and receipt schema
   with fresh-repo restore test; prove a dirty tree survives removal of its
   original ODB, and that blob writes never land in source.
3. Typed append-only ref transaction, restart protocol and verifier; prove
   interrupted apply cannot report success and unchanged/changed retries
   cannot rewrite old refs. Register both CLI commands; verify absent legacy.
4. Packaging and operator-facing docs: `vp pack`, commit updated
   [`archive/repo-jj-archive.mjs`](/archive/repo-jj-archive.mjs) with sources,
   exercise source CLI **and** unchanged launcher bundle fallback; update
   [`archive/README.md`](/archive/README.md) with qualified `dl` story and
   plan → apply → verify → explicit human follow-ups, not an invitation to
   rerun into its populated legacy label.

Extend the disposable jj+Git pytest precedent at
[`tests/integration/repo_jj_archive.test.py`](/tests/integration/repo_jj_archive.test.py)
with `tests/integration/repo_jj_archive_adopt.test.py` or a focused section;
use `.test-agent/repo-jj-archive/tests/` scratch (the earlier
`.test-agent/archive-migration/fixture-gpt6sol/` is a reference, never a
production target). Required fixture matrix:

| Fixture | Evidence/assertion |
|---|---|
| Clean branch, detached divergent 374-style chain, separately selected recorded remote baseline | Exact full OIDs/ref maps, `N` against specified baseline, deduplicated destination delta, no unverified “unpushed” claim; plan leaves both repos untouched. |
| Tracked edit/deletion, staged versus unstaged, untracked new/symlink, ignored DB, tracked key-like path and tracked runtime path | Manifest contents/modes/tree; ignored paths absent; tracked paths not falsely excluded; staged distinction reported, privacy review/unexplained-path blocker; no contents in output. |
| Inert `.jj/` placeholder, valid jj with Git-covered and jj-only/failed-inspection heads | Placeholder classified and excluded, Git-covered accepted, jj-only/unknown blocked; **no source jj writes**. |
| Temp-index regression probe and real isolated stage | Reproduce that temp-index `git add` adds source ODB blob, then assert plan/apply source loose **and packed** objects, refs, index bytes, worktree and `.jj` remain byte-for-byte unchanged. |
| Branch literally named `head`/`working-copy`, annotated and lightweight tag, stash with older reflog tip, notes/replace/nonstandard ref, reflog-only candidate | Names round-trip without lane collisions; annotated tag object's OID in `refs/tags` (Git rejects placing it under `refs/heads`); every selected stash/reflog object pinned; unclassified candidate blocks. |
| Unchanged retry; changed worktree; changed branch; preexisting old harvest prefix; ref race | Identical receipt and refs on retry, worktree content-addressed new pin, branch requires new generation, no overwrite/delete on occupied prefix or concurrent update. |
| Fault at staged bundle, object transfer, receipt creation, and pin transaction | No “complete” without verifier; resume only from matching receipt/intent, preserve preexisting refs, fail on mismatch. |
| Bundle restore from empty repository; source directory moved/removed before `verify-adoption` | Full closure including synthetic commit and tag/stash tips; verifier works with `--dest` + receipt ref alone; missing/tampered bundle or ref fails distinctly. |
| Existing archive dirty/ghost/conflict/remote mismatch and absent archive | Existing archive never snapshotted or reconciled; blocked no ref mutation; new full clone only on apply after plan, no checkout reset. |
| Source CLI and committed bundle through unchanged launcher, `--json` and human mode | Single stdout JSON line on successful calls, failure diagnostics stderr only, bundle fallback recognizes both commands, destination worktree unchanged by adopt. |

Run `pnpm check`, `pnpm build` / `vp pack`, and the focused pytest suite;
committed bundle must match its source. The old
[`script/deprecated-harvest-legacy-repo.sh`](/script/deprecated-harvest-legacy-repo.sh)
remains a visibly unsafe escape hatch, **not** deleted or repurposed during
this brief. Consider its retirement only after tested replacement covers
branch/HEAD/dirty-tree transport *and* the expanded tagged, stash/reflog,
privacy, source-read-only, immutable retry, complete-bundle, source-independent
receipt and launcher scenarios; document behavior differences for existing
users and obtain a separate operator decision. Its optional push is **not**
replacement scope.

## Open implementation risks and explicitly separate follow-ups

- The Git object/hash format, weird ref/path bytes, index extensions,
  symlink/path races and Git's filter or maintenance behavior need fixture
  evidence. Block unknown variants instead of weakening the source read-only
  guarantee. Holding writers is still a necessary operator precondition.
- A receipt ref can be cloned without its sibling private bundle; verification
  must detect that. Local private storage is not an off-host backup, and
  independently backed-up artifacts require separate owner policy.
- Importing refs into a jj-colocated destination may have jj visibility or
  ref-namespace interactions: test with the installed jj version; do not
  auto-reconcile a destination merely to make a test green.
- **Separate operator follow-ups only:** selected deployment base/workspace,
  running-state handoff and consistent backup, shim/consumer change,
  publication after reachable-history/credential review, and eventual source
  retention/disposal. None is implied by `custodyVerified`.

## Cross-references and design clarification

- [Authoritative custody design](/design/archive-migration/draft0-syn2.gpt6sol.md): supplies the plan-first and three-permission boundary; this brief pins down ref lanes, receipt location, retry and tests without broadening its scope.
- [Fixture study](/design/archive-migration/draft0.gpt6sol.md): first demonstrated forced ref updates, pre-snapshot bundle gaps and `.jj` capture; use fixtures rather than replaying production.
- [Archive toolkit contract](/archive/README.md): existing command/launcher, jj health and one-JSON-line conventions; `refresh --update false` is **not** read-only on an existing checkout.
- [Ghost-head incident](/design/repo-jj-archive/incident-ghost-heads.glm53.md): jj health is a useful preflight but cannot replace checking exact Git objects and refs.
- [Deployment workspace premise](/design/archive-deployment-premise/draft0.glm53.md): unresolved deployment architecture, explicitly *not* decided here.

**Clarification to syn2:** its example `verify-adoption --receipt FILE`
underspecifies the promised *archive-carried* receipt. This brief chooses
`--dest DIR --receipt <full archive receipt ref>`; an exported JSON file is
not canonical evidence. It also makes the receipt an expected-transfer
manifest installed **before** recovery pins so an interrupted transaction is
diagnosable, not a claim of success until independent verification passes.
