---
type: Design
title: Archive adoption custody contracts
description: Buildable interfaces, trust boundaries, retry states, and verification gates for a domain-structured Effect archive toolkit.
resource: /design/archive-toolkit/custody-contracts0.gpt6sol.md
tags: [compfuzor, archive, adoption, custody, effect, git]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-27 }
stale_after: 2026-11-27
sources:
  - id: implementation-brief
    resource: /design/archive-migration/brief0.gpt6sol.md
    title: Archive adoption Git custody implementation brief
  - id: governing-design
    resource: /design/archive-migration/draft0-syn2.gpt6sol.md
    title: Receipt-driven source custody design
  - id: current-toolkit
    resource: /archive/README.md
    title: Archive toolkit contract
---

# Custody contracts for `adopt` and `verify-adoption`

## Situation and boundary

The [implementation brief](/design/archive-migration/brief0.gpt6sol.md) and [governing design](/design/archive-migration/draft0-syn2.gpt6sol.md) require Git source custody **before** deployment or retirement: read-only source inventory, isolated private staging, an immutable receipt and refs, and verification without the legacy checkout. This note translates those guarantees into interfaces for `archive/src/{cli,repository,recovery,custody,runtime}`. It is an implementation seam, not a new authority to fetch an existing archive, modify a legacy repository, reconcile a destination, publish, or dispose of anything. Research question: can the result be reproduced from the receipt and vault bundle alone, with neither a live source nor trust in jj health as a substitute for Git closure?

Current [`health.ts`](/archive/src/health.ts) materializes jj visible heads and conflicts; it does **not** verify Git closure, and its ordinary `jj log` and `jj bookmark list` calls can snapshot/import on read. Do **not** use it unchanged for custody. [`refresh.ts`](/archive/src/refresh.ts) calls `jj status` even with `--update false`, so existing destinations must not be passed to it. [`jj.ts`](/archive/src/jj.ts) uses UTF-8 `execFile` strings and trims output: do not use its string parsing for NUL-delimited paths or arbitrary ref bytes. The current package has Gunshi, not Effect; CLI dependency wiring and installation belong to the separate CLI owner. `~/archive/Effect-TS/effect` exists as the local upstream reference (no `llms.txt` found; `LLMS.md` exists). These contracts use `Effect.Effect<Success, CustodyError, Services>` as a *shape*, not a claim that a particular upstream platform service already provides byte-safe Git plumbing.

## Domain ownership and trust boundaries

| Group | Owns | Must not own |
|---|---|---|
| `repository/` | Binary-safe Git invocation; source and destination probes; immutable value decoding for OIDs, paths, refs; tested jj read-only query/preflight adapter | Policy decisions, `jj status`, destination ref creation as a side effect of probing |
| `recovery/` | Ref lane codec, collision/prefix checks, Git ref transaction and resume decision | Worktree snapshot content or receipt serialization |
| `custody/` | Inventory/admission, scratch stage, bundle/vault, canonical receipt, independent verifier, apply orchestration | Deployment, fetch on existing destination, source-side writes |
| `runtime/` | Effect services for process execution, filesystem, random bytes, clock, atomic durable vault writer and injectable faults | Global configuration or untestable implicit cwd |
| `cli/` | Argument validation, typed JSON/human presentation, nonzero failure and one stdout JSON line on success | Direct Git or filesystem mutations |

Use `repository/git.ts` with argv arrays, explicit cwd/Git env and raw `Buffer` output (bounded, or stream when large); no shell interpolation or `stdout.trim()` on path lists. Prefix source probes with `GIT_OPTIONAL_LOCKS=0`, disabled optional maintenance and controlled config/env; reject user-config features not safely understood. Make process environment selection explicit for each subprocess; setting `GIT_INDEX_FILE` alone leaves object writes in the source. Effects should describe both typed failures and service requirements; fatal bugs remain defects, not `catch`-and-print success. The only privileged capabilities in apply are private vault creation, destination ODB import, and new custody refs. Plan receives none of the latter two capabilities.

Suggested TypeScript contracts (interfaces, not prescribed concrete file names):

```ts
type Oid = string & { readonly __oid: unique symbol }; // validated 40 or 64 hex against objectFormat
type RefName = string & { readonly __ref: unique symbol }; // lossless UTF-8 + check-ref-format
type RepoPath = string & { readonly __path: unique symbol }; // lossless UTF-8, never newline-parsed
type Sha256 = string & { readonly __sha256: unique symbol };
type ObjType = "commit" | "tag" | "tree" | "blob";
type PathEntry = Readonly<{ path: RepoPath; mode: string; oid: Oid }>;
type Tip = Readonly<{ name: RefName; oid: Oid; type: ObjType; peeledOid?: Oid }>;
type SourceFingerprint = Readonly<{
  canonicalInputsSha256: Sha256;
  indexSha256: Sha256;
  sourceOdbListingSha256: Sha256; // loose and packed file inventory, before/after stage
  worktreeManifestSha256: Sha256; // bytes/metadata of included input, not only Git status
  jjStoreFingerprint: Sha256 | null;
}>;
type Issue = Readonly<{ code: string; subject?: string; reason: string }>;
type Plan = Readonly<{
  schema: "compfuzor.archive-adoption-plan/v1";
  identity: { label: string; generation: string; legacyRealpath: string; destinationRealpath: string };
  source: SourceInventory;
  destination: DestinationBaseline;
  selection: Readonly<{ pins: readonly PinIntent[]; snapshot: SnapshotIntent | null }>;
  pathReview: PathReview | null;
  fingerprints: SourceFingerprint;
  blockers: readonly Issue[];
  warnings: readonly Issue[];
  retirementUnresolved: readonly Issue[];
}>;
type CustodyError =
  | { _tag: "InvalidInput" | "UnsupportedRepository" | "InspectionFailed"; detail: string }
  | { _tag: "Drift" | "OccupiedNamespace" | "DifferentReceipt"; detail: string }
  | { _tag: "BundleInvalid" | "RefRace" | "VerificationFailed"; detail: string };

interface Inventory {
  plan(input: AdoptInput): Effect.Effect<Plan, CustodyError, GitRead | FileRead | JjRead>;
  recheck(plan: Plan): Effect.Effect<void, CustodyError, GitRead | FileRead | JjRead>;
}
interface ReadOnlyJj {
  visibleHeadsAndConflicts(repo: string): Effect.Effect<JjView, CustodyError, ProcessRead>;
  sourceGitCoverage(repo: string, selectedGitTips: readonly Oid[]): Effect.Effect<JjCoverage, CustodyError, ProcessRead>;
}
interface PrivateStage {
  prepare(plan: Plan): Effect.Effect<StagedCustody, CustodyError, GitRead | PrivateGitWrite | FileRead>;
}
interface BundleVault {
  seal(stage: StagedCustody, plan: Plan): Effect.Effect<SealedBundle, CustodyError, PrivateGitWrite | VaultWrite>;
  open(receipt: ReceiptV1, dest: string): Effect.Effect<VerifiedBundle, CustodyError, VaultRead | PrivateGitWrite>;
}
interface Verifier {
  verify(dest: string, receiptRef: RefName, legacy?: string): Effect.Effect<Verification, CustodyError, GitRead | VaultRead | JjRead>;
}
interface Adoption {
  apply(input: AdoptInput): Effect.Effect<Verification, CustodyError, GitRead | FileRead | JjRead | PrivateGitWrite | VaultWrite | DestinationWrite>;
}
```

`SourceInventory` includes full HEAD tree/path manifest; full ref map, tags and peeled targets; all reflog entries and dangling candidates with explicit `pin` or `not-required` disposition and reason; staged vs unstaged paths, ignored/excluded paths, sensitive tracked path classifications, jj coverage, selected baseline URL/ref/OID and deduplicated comparisons. `DestinationBaseline` contains **exact** protected Git refs and worktree/index observations as well as their digest; a hash alone cannot explain a later drift. `PinIntent` includes source kind, full original name or stable `kind+OID` candidate identity, original type/OID, full destination ref/type/OID and provenance. Neither opaque strings nor arbitrary user-provided refs may bypass validation.

## Inventory and admission gates

1. Canonicalize roots and compare ancestry and symlink aliases. Reject source `.git` file/linked worktree, bare/shallow/partial/promisor/sparse/alternates/filter/LFS/submodule variants unless their closure and bytes are actually proven by a separately designed extension. Plan must inventory what remains inspectable and emit named blockers; inspection failure is not an empty set. Reject unrepresentable path/ref bytes rather than lossy JSON; parse Git NUL output as bytes and require round-trip UTF-8 before claiming this v1 receipt describes it.
2. Probe `git for-each-ref`, HEAD, index stages/status, reflogs **including old stash entries**, and `fsck` dangling candidates without `--lost-found`. `fsck` may report corruption and is not permission to repair or fetch. A raw reflog record stays provenance; pin identity for the same selected candidate is kind + full OID. A dangling noncommit object is inventoried, not presumed wanted. Candidate work without disposition blocks apply. Input disposition/exclusion file hashes and operator reasons are frozen.
3. Inspect jj source without `jj status`, `jj git export` or any command with hidden source writes. **New `repository/jj.ts` query seam** must invoke *only tested read-only* jj queries, with global `--ignore-working-copy` and `--at-op=@` (or a fixed observed operation ID) to avoid snapshot and divergent-operation integration; never call current `health.preflight()` or `remotes.remoteDiff()` unchanged in custody. `jj --help` on installed jj 0.45.1 confirms `--ignore-working-copy` disables working-copy snapshot/update and `--at-op=@` implies it and avoids merging divergent operations; the same help cautions that mutating subcommands can still run at a past op, so argv must be an allowlist. Prove in fixtures whether Git auto-import or other writes can still occur for each allowed query; block if so. Valid jj heads must all be shown reachable from selected Git tips; otherwise block. Invalid `.jj` placeholder is recorded as left behind. Failed jj inspection blocks; no inferred absence. Destination preflight uses the new read-only equivalent of `preflight()` with zero conflicts **and** separate exact Git refs/ODB, clean worktree/index, declared origin URL check via read-only Git config; do not adopt a non-jj destination in place.
4. Produce a proposed Git path/mode/blob manifest for a dirty snapshot using private scratch. Never let untracked `.git`/`.jj` components, ignored files or excluded paths into it; tracked internals **block**, not silently disappear. Tracked sensitive or runtime-like files remain explicitly named and require privacy classification, with no content/secret logging. Unmerged index blocks. Record separately what the one worktree tree cannot preserve about staged versus unstaged states. Protect symlinks as links, not followed targets; refuse file acquisition through paths escaping root or changing underfoot. Dirty capture must be *possible* after exact manifest/path review rather than permanently blocked by conservative path classifiers; see the narrow review contract below.
5. A plan is a read-only *observation*, not a reservation. Apply performs a fresh plan and compares canonical input, policy files, source fingerprint and destination baseline, stopping on drift. Require writers stopped throughout; before and after staging compare source index/config/refs/reflogs, ODB loose **and packed** listings, included worktree input and `.jj` fingerprints. Checking object counts alone misses substitutions. Unknown baseline freshness yields `unknown`, not zero or “unpushed.”

### Narrow path review rather than a blanket exemption

The brief's `--dispositions FILE` applies to **kind+OID candidates** (reflog/dangling work), not worktree paths; do not repurpose it as a generic privacy bypass. Propose a separate `--path-review FILE` JSON input, recorded by SHA-256 and parsed strictly. It binds an **exact reviewed snapshot manifest digest**, plus per-path entries keyed by exact `path + mode + blobOid` for *included* sensitive/runtime-classified paths. Each entry states `local-custody-approved` with a nonempty operator rationale and classification (e.g. tracked credential, runtime-like file); it explicitly says nothing about safe publication. A separate `stagedVsUnstaged: "single-tree-approved"` with rationale is required when that distinction exists; the receipt records that original index/worktree split **is not recoverable**. Do not put file contents in review input, plan output or receipt. Reject blanket globs, approvals for unknown path/OID, stale manifest digest, missing reason, unclassified suspicious included paths or any attempted exclusion of tracked internals. The receipt records canonical decisions and review file hash, making it independently auditable without requiring the file after source retirement. An unchanged manifest may reuse the same review; changed blob or path needs a new review. The CLI flag and schema need parent sign-off, but the dependency should be a typed `PathReview | null`, **not** an implicit boolean:

```ts
type PathReview = Readonly<{
  schema: "compfuzor.archive-path-review/v1";
  manifestSha256: Sha256;
  fileSha256: Sha256;
  included: readonly Readonly<{
    path: RepoPath; mode: string; oid: Oid;
    classification: "credential" | "runtime-state" | "other-sensitive";
    decision: "local-custody-approved";
    reason: string;
  }>[];
  stagedVsUnstaged: null | Readonly<{ decision: "single-tree-approved"; reason: string }>;
}>;
```

The external JSON uses explicit `null` for absent optional wire fields (including clean `snapshot: null`, no path review, no exclusion/disposition file hashes). Effect internals may use `Option`, but the v1 receipt encoder must emit required keys with JSON `null`, and the strict decoder must reject missing keys as well as wrong types. The path-review input itself omits `fileSha256` (a file cannot contain its own hash); the loader computes and records it in the receipt. This exact `--path-review FILE` contract and explicit single-tree decision were approved by the parent.

## Private stage and isolated bundle proof

`StagedCustody` is a private scratch bare Git repository with all selected originals, a temporary index and the optional deterministic synthetic commit. It is not an alias to source `.git`: `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY` and alternates must be wired explicitly on every staging command. Source alternates are **read access only**; scratch receives all new blobs, trees and commits. Stage from HEAD tree, then tracked worktree changes and selected untracked files from a NUL-safe manifest. Fixed `worktree-v1` author/committer/message/time; parent is original HEAD. Only create synthetic commit when tree differs from HEAD tree. Compare resulting tree *and path/mode/blob entries* with plan before continuing; fail on active external filters unless proven reproducible and non-writing.

**The alternates trap:** `git bundle create --all` in scratch while scratch still depends on source objects is not by itself evidence of a source-independent archive. Explicitly materialize **reachable closure for every selected source tip and synthetic commit** in scratch's private ODB (e.g. read-only object pack streaming from source, `index-pack` into scratch; never a pack written into source); install private staging refs for every tip. Remove/disable alternates for the proof, and check `cat-file`/`fsck` of scratch before bundling. Create the bundle from these refs with no excluded prerequisites; inspect bundle heads and prerequisites, require exact selected head OIDs and **no prerequisites**. Restore/unbundle to an empty new repository with neither source nor destination alternate, and check every pinned object, commit ancestry, annotated tag target and full snapshot path/mode/blob manifest there. An empty-repository `bundle verify` alone or a successful check against populated destination is insufficient. An OID-hash mismatch between source and destination Git object formats must block before transfer.

Write bundle and intent to `dirname(dest)/.compfuzor-adoptions/<sha256(canonical dest)>/<cryptographic-random-128+-bit-id>/` outside both worktrees. Create with no-follow/exclusive access, owner-only `0700` directories and `0600` files, atomic rename and fsync file and containing directory before any destination ref update. Do not delete ambiguous incomplete runs automatically. Source paths/credentials in receipts and bundles are sensitive; no public deployment-tree artifact. Avoid a timestamp-only run identity. The intent binds plan hash, selection, bundle SHA-256, exact staging heads and prospective receipt/ref set; it is diagnosis, not proof of completion.

## Receipt, immutable namespace, and apply state machine

`ReceiptV1` is a **strictly validated**, canonically serialized schema, `compfuzor.archive-adoption/v1`, in `adoption.json` of a fixed-metadata parentless metadata commit at `refs/adopt/receipts/<label>/<generation>`. Never embed that commit's OID in its JSON. Include original source ref names/OIDs/types and HEAD tree paths, candidate dispositions/provenance, jj classification, staged-vs-unstaged caveat, snapshot paths/OIDs if any, exact pre-import destination ref/worktree baseline, file hashes, typed pin mapping, sealed bundle constrained relative vault path/hash/heads, immutable checks, and unresolved retirement items. A clean source has `snapshot: null`; a dirty source's commit/tree and paths are individually testable. Canonicalization includes deterministic sorting and serialization, Git object format and schema version; UTC creation time is fixed at first creation and comes from existing receipt on retry, **never regenerated** for equality. Unknown incompatible schema/fields fail closed. Receipt claims an *expected transfer*, not successful verification.

Typed ref codec: branch → `refs/heads/harvest/<label>/<generation>/branch/<encode(original branch)>`; HEAD → `.../head/<OID>`; dirty tree → `.../working-copy/<parent>-<tree>-worktree-v1`; tag → `refs/tags/harvest/<label>/<generation>/<encode(original tag)>`; stash, older stash/reflog, notes, replace, other refs → `refs/adopt/custody/<label>/<generation>/<kind>/<encode(full identity)>`. Encode original ref bytes injectively (length-prefixed hex fixed-size components), round-trip and `check-ref-format` every output. Keep annotated tag **tag object** as tag; do not activate `refs/replace` by mirroring original location. Validate `label` and `generation` as exact Git ref components and reject invalid input, never sanitize or normalize; validate full ref and length; reject reserved namespace and file/directory prefix conflicts, including legacy `harvest/<label>/head` and `working-copy`.

```text
fresh plan -> inspect full namespace and destination pre-state
            -> private stage + source drift check
            -> self-contained bundle and empty-restore proof
            -> durable vault intent + deterministic receipt blob/commit
            -> destination object import (refs unchanged)
            -> atomic compare-and-create transaction: receipt ref and all missing pins
            -> independent verifier; only then report custodyVerified=true

existing receipt -> validate receipt and intent first, before minting anything
                 -> compare same source input/selection/mapping and stored first pre-state
                 -> require matching refs or missing refs only; no writes to mismatched refs
                 -> import missing objects as necessary, create missing pins with expected old zero
                 -> verify, never report complete solely because receipt exists
```

The parent approved a **single atomic `git update-ref --stdin` compare-and-create transaction for receipt and all pins**. This deliberately refines the brief's receipt-first ordering: pre-transferred objects and a durable bundle make one atomic namespace transition preferable. Still support matching-receipt/partial-pins states from interrupted or externally modified installations: retain the *same* receipt commit and vault evidence and allow only missing-pin completion; verifier rejects incomplete state. A ref with equal OID is a no-op; another OID, occupied prefix, or changed source input under same generation is a hard stop and asks for a new generation. No reset, prune, force-update or auto-disposal. Before staging precheck all names; transaction's expected-old zero closes the final race. A preexisting receipt requires comparing recorded fingerprint and mappings against a **new** inventory while discounting only this receipt's own installed refs from pre-state. A retry after source removal is **verification**, not re-adoption; do not reinterpret changed destination state as same-generation input. An orphan intent/bundle without receipt requires deliberate diagnosis, not guessing which run to resume.

`apply` with an absent destination may clone once *after inventory and plan approval*, full jj-colocated and no depth, then recheck destination pre-state; existing destination never calls `refresh`. Destination object import must not check out or move `main` or change remotes; verify after refs that main worktree/index remain identical and jj view has no missing/conflicted visible heads. If Git object import fails before refs, leave private artifacts for diagnosis; if verification fails after refs, report failure, retain receipt/refs/artifacts, and never undo them automatically. Return a structured status only on fully checked success.

## Independent verifier contract

`verify(dest, fullReceiptRef)` reads `REF:adoption.json` from the destination ODB, validates commit type, exact schema, receipt identity and codec round-trips, and obtains the receipt commit OID from the ref. It resolves the vault path relative to destination parent, rejects any `..`, absolute path, symlink component, wrong archive-id or outside-vault target, then hashes the bundle and checks its advertised heads and fresh empty-repository restore. It independently recomputes each expected ref name, reads exact destination ref type/OID, proves every pin's reachable object closure and original HEAD tree and synthetic tree **path/mode/blob manifest**; do not let a receipt's own `checks` booleans attest to themselves. Check jj visible heads and conflicts, reporting destination drift (worktree/index/protected pre-state) separately from historical custody. `--legacy` is optional and adds *diagnostic* source drift/jj comparison; absence of legacy cannot make verified custody fail.

```ts
type Verification = Readonly<{
  receiptRef: RefName;
  receiptCommitOid: Oid;
  custodyVerified: boolean; // true only after all required refs/objects/bundle/manifest checks
  custodyFailures: readonly Issue[]; // false + nonzero command exit on required-check failure
  sourceDrift: "absent" | "unchanged" | "changed" | "unknown";
  destinationDrift: "unchanged" | "changed" | "unknown";
  retirementUnresolved: readonly Issue[]; // even with custodyVerified=true
}>;
```

A valid plan containing blockers is a successful **plan result**, but `apply` refuses blockers and unresolved candidate work. Failed verification must be nonzero, stderr diagnostic and **no partial JSON**; a successful custody verification may still list retirement unresolved items. Never emit “safe to delete.” Git custody does not establish ignored DB/WAL or jj op-log preservation, off-host backup, credential publish safety, or correct runnable workspace.

## Coherent implementation slices and acceptance ownership

1. **Inventory/admission owner (GX):** binary-safe repository probe, immutable plan and admission table, source/destination **tested read-only** jj query seam, blocker classification, exact baseline counts and policy-file/path-review hashes. Fixtures: detached chain against *named* local baseline, weird path bytes block, dirty/staged/untracked/ignored/tracked-sensitive state and exact path review, old stash/dangling classifications, invalid/valid jj, alternate/partial/linked checkout blockers. Assert source ODB loose+packs/index/refs/config/reflogs/worktree/jj byte fingerprints before/after plan. Commit with fixtures, not CLI registration alone.
2. **Private stage/bundle owner:** scratch ODB isolation, synthetic commit, private closure transfer, no-prerequisite bundle, vault writer and empty restore proof. Fixtures: temporary-index source-ODB regression, no new source object even after untracked staging, annotated tag and older stash, source ODB physically unavailable for fresh restore, corruption/tampering failure, failpoint before durable bundle. Expose `StagedCustody`/`SealedBundle`, not a Git command string to the CLI.
3. **Receipt/verifier owner:** schema/codec, strict parser, Git-only `verify-adoption`, private path safety, bundle restore, ref/manifest/object and optional source checks. Fixtures: absent legacy, missing/mismatched tag, removed bundle, escaping vault symlink, wrong version, changed destination worktree reported distinctly. This owner should implement verifier *alongside* schema before `apply` can claim success.
4. **Apply/recovery owner (Sol medium):** explicit ref namespace checks, compare-and-create transaction, destination object import, receipt-first or atomic transaction protocol, retries and failpoints. Fixtures: collision with old harvest prefixes, branch named `head`, same-input retry no-op, changed branch/worktree generation conflict, race after precheck, failures at bundle/object/receipt/pins and recoverability without overwrites. Integrate destination **read-only** jj health and checkout fingerprint, never auto-heal. Agree exact `PinIntent` / `ReceiptV1` handoff with GX before either owns apply orchestration; GX can implement most inventory, staging and verifier independently while Sol owns transaction/retry core.
5. **CLI/packaging owner (separate):** Effect CLI wiring with top-level `adopt` and `verify-adoption` commands (not nested or renamed), `--json` stdout contract, launcher source/bundle fallback, docs, `pnpm check`, build and pytest. Delegate infrastructure creation to runtime/repository seams and avoid parallel edits to a shared entrypoint. Source `.ts` is the development interface; committed bundle must match build sources.

All fixtures must be disposable; none of these slices should run an operation on the production `dl`, archive checkout, or remote. Each slice is a coherent commit with an evidence note, not a partial success claim.

## Resolved parent decisions and remaining proof gates

1. **Read-only jj coverage:** which *verified* jj command/revision expression inspects all wanted heads without source writes on the installed jj version? Default block valid `.jj` until fixture proof; do not water down the guarantee to `visible_heads()` alone if hidden/unexported jj-only work matters.
2. **Approved:** `--path-review FILE` (separate from kind+OID `--dispositions`) and exact manifest-bound approval above; implement with a strict null-preserving receipt. Do not block *all* tracked credentials forever or silently mark them safe for publication.
3. **Approved formats:** inventory both SHA-1/SHA-256; source/destination format mismatch blocks. jj repository/object-format support must be proven per format or a named blocker; raw Node Buffer behind repository/runtime adapters is acceptable if upstream process APIs lose bytes.
4. **Approved transaction:** one atomic receipt-plus-all-pins compare-and-create; support matching receipt partial states without generating a different receipt on retry, as detailed above.
5. **Approved v1 target, gated:** absent destination via safe full jj-colocated clone *after dedicated fixture proof*. An initial named blocker during implementation is acceptable; do not claim complete v1 until this path works. Existing destination busy/dirty detection needs explicit testable criteria; do not call `refresh` and hope its `--update false` is non-mutating. Parent retains the **top-level command names** and five domain folders.

The concrete shared wire types are now in [`model.ts`](/archive/src/custody/model.ts), with canonical receipt parsing/encoding and injective lane mapping in [`codec.ts`](/archive/src/custody/codec.ts). They are a pure data boundary usable by GX while Effect service orchestration is developed separately. `parseReceipt` requires canonical UTF-8 JSON, explicit nulls, validated SHA format and receipt-to-pin mapping. Pure validation is not a substitute for Git `check-ref-format`, source closure, no-symlink vault opening, and independent verifier proofs.

## Cross-references

- [Adoption brief](/design/archive-migration/brief0.gpt6sol.md): authoritative scope, receipt fields, typed ref lanes and acceptance matrix; this document makes the execution boundaries and handoffs explicit.
- [Governing synthesis](/design/archive-migration/draft0-syn2.gpt6sol.md): separates source custody from publication, deployment and retirement, and records the temporary-index source ODB failure.
- [Toolkit README](/archive/README.md): existing CLI stdout, launcher and build conventions; adoption must not borrow `refresh`'s source/destination mutations.
- [Archive health](/archive/src/health.ts): its ordinary jj commands may snapshot/import even when described as no-mutation; custody needs a newly tested read-only jj seam in addition to Git object/bundle checks.
