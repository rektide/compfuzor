---
type: Review
title: Archive custody safety — transfer and verification seams
description: Independent review of snapshot admission, private bundle/vault, immutable retry, ref installation, and source-independent verification.
status: draft
generated: { by: model:gpt6sol, at: 2026-09-28 }
sources:
  - resource: /design/archive-migration/brief0.gpt6sol.md
    title: Git custody implementation brief
  - resource: /design/archive-toolkit/direction0.gpt6astra.md
    title: Accepted archive toolkit direction
  - resource: /design/archive-toolkit/core-review0.glm53.md
    title: Earlier recovery/codec review
  - resource: /design/archive-toolkit/safety-review0.gpt6luna.md
    title: Independent source-acquisition review
---

# Transfer and verification safety review

## Scope and verdict

Read current `custody/{inventory,stage,apply,vault,verify}.ts`, inventory's probe/decoder, `recovery/{retry,transaction,git-ref-store}.ts`, codec and focused tests. No production repository was touched; a disposable staged-index fixture and a missing-blob Git probe live under `.test-agent/custody-review-sol/`. The reported 29 passing tests were not rerun. Existing-destination only, tree/blob-tip rejection, and unfinished CLI packaging are intentional boundaries, **not findings**. The preceding [Luna checkpoint](/design/archive-toolkit/safety-review0.gpt6luna.md) already demonstrates source/destination alias writes, executable Git configuration, symlink acquisition, and truncated ignored inventory; avoid counting those twice. In parallel with those blockers, the index-only omission below prevents a release-level custody claim.

## Findings

### H1 — A ready plan can silently omit an index-only version

**Release blocker: incomplete admitted work.** The source status records both staged and unstaged changes, but the preview always starts at HEAD and restages **the worktree**, not the index ([`stage.ts:84-89,606-625`](/archive/src/custody/stage.ts)). If the worktree content is restored to HEAD after staging another version, the preview tree equals HEAD and returns `null` ([`stage.ts:743-750`](/archive/src/custody/stage.ts)). Inventory requires a review only when `proposal !== null` ([`inventory.ts:363-442`](/archive/src/custody/inventory.ts)); a `null` proposal can reach `state: "ready"` with only HEAD/branch pins ([`inventory.ts:672-689`](/archive/src/custody/inventory.ts)). The staged blob was never included in a named pin or tree, despite [`brief0`](/design/archive-migration/brief0.gpt6sol.md#read-only-inventory-and-guarantee-set) requiring an explicit stop if the index/worktree distinction must be recoverable. The `staged-vs-unstaged` warning does not classify the omitted blob or prevent apply; `prepareSnapshot` likewise mints no working-copy commit.

**Executed fixture:** initialize and commit `f = "base\n"`; write `"INDEX-ONLY SECRET\n"`, `git add f`, then write `"base\n"` into the worktree; clone a jj-colocated destination and plan. Observed `state=ready`, `blockers=[]`, `proposedSnapshot=null`, pins `head,branch`; `git rev-parse :f` was `14f750a…` versus `HEAD:f` `df967b9…`. Plan warned `staged-vs-unstaged` yet required no path review. The staged blob exists in the source ODB but is unpinned and disappears when the source ODB is removed.

**Regression:** reproduce that exact three-state fixture; reject apply with a named `index-content-not-preserved`/review-required blocker (or explicitly add index custody) whenever the index holds an independently wanted version not represented by the synthetic tree. Require an explicit lost-split acknowledgment even when the selected worktree tree equals HEAD; an approval cannot manufacture index recovery, so do not claim it in the receipt. Include staged-only additions/deletions and staged-content-then-restored-worktree variants.

### M2 — Existing vault directories need no owner-only permissions or ownership

`mkdirLevel` accepts any existing nonsymlink directory ([`vault.ts:184-205`](/archive/src/custody/vault.ts)); a preexisting `.compfuzor-adoptions` root or archive-hash directory with mode `0777` is reused. New run directories and files are `0700`/`0600`, but another user with write access to the parent directory can rename or unlink the entire run directory after sealing. The verifier checks types/symlinks, not owner or permissions ([`vault.ts:115-146`](/archive/src/custody/vault.ts)). This defeats the brief's owner-only vault and durable receipt/bundle guarantee; there is also a parent-component swap race between `lstat` and ordinary-path `readFile` ([`verify.ts:529-563`](/archive/src/custody/verify.ts)). An unrelated user's writable sibling of an existing archive is not necessarily trustworthy storage.

**Regression:** precreate the vault root or archive-hash directory with `0777`, run `createVaultRun`/`sealBundle`, and assert refusal before any bundle is sealed; test wrong ownership, existing symlink, and restore after swapping a directory component. Verify with the vault moved alongside the archive, not by consulting its old absolute path. Enforce owner and restrictive mode at each existing level, and use anchored descriptors or a revalidated open+`fstat` identity when reading the bundle; do not silently chmod user-created directories.

### M3 — Optional source drift hashes an unsound newline-delimited path protocol

`sourceDriftOf` builds `git hash-object --stdin-paths` input with `manifest.map(path).join("\n")` ([`verify.ts:733-756`](/archive/src/custody/verify.ts)), while `repoPath` explicitly accepts newline-bearing filenames ([`codec.ts:42-52`](/archive/src/custody/codec.ts)). Such a name splits into two path requests and misaligns output with the receipt manifest; quoted paths may also be interpreted by Git rather than byte-exactly. Clean tracked symlinks are hashed through their targets rather than as mode-`120000` link text (the comment at [`verify.ts:733-736`](/archive/src/custody/verify.ts) acknowledges false drift). This is *not* merely cosmetic when called from apply: after the atomic ref install, [`apply.ts:313-333,548-563`](/archive/src/custody/apply.ts) requires `sourceDrift === "unchanged"` and returns failure despite successfully installed custody refs. The symlink acquisition problem is already covered by Luna; this is the separate **post-install verification gate** and newline-filename issue.

**Regression:** clean tracked `f\npart` (and separately a clean tracked symlink) in a ready fixture; `applyAdoption` should not fail with `source-drift` after installing its refs. Compare accepted paths with byte-safe NUL input where Git supports it, otherwise use per-path exact byte-safe inspection; `lstat` and hash symlink text without following targets. More generally, perform source drift checks before commit of refs, then report post-install drift as diagnostic without mislabeling an installed, independently verified transfer as nonexistent.

## Reviewed and found structurally sound

- `applyAdoption` seals and restores the source-only bundle before destination import, rechecks source/destination before the ref transaction, and independently verifies after installation ([`apply.ts:488-565`](/archive/src/custody/apply.ts)). Object-only transfer via `bundle unbundle` and receipt `index-pack` does not ask Git to update existing destination refs, HEAD or worktree. A failed post-transfer check leaves unreachable destination objects, not a moved ref. This assumes the source/dest alias blocker in Luna's review is resolved **before** import.
- Retry reads the exact receipt blob from its ref, checks sealed intent and bundle restoration, discounts only the receipt's own pins against original pre-refs, and does not mint a new timestamp/bundle on a same-generation retry ([`apply.ts:435-485`](/archive/src/custody/apply.ts), [`retry.ts:48-118`](/archive/src/recovery/retry.ts)). `GitRefStore` builds one `update-ref --stdin --no-deref` compare/create transaction ([`git-ref-store.ts:64-84`](/archive/src/recovery/git-ref-store.ts), [`transaction.ts:127-169`](/archive/src/recovery/transaction.ts)). A ref-race cannot silently overwrite a protected ref.
- Receipt is fetched from the destination and its commit shape checked independently; pin identities, exact types/OIDs, HEAD and snapshot tree manifests, checksum, bundle heads, and fresh no-prerequisite restore are rechecked without consulting the source ([`verify.ts:322-590`](/archive/src/custody/verify.ts), [`stage.ts:869-965`](/archive/src/custody/stage.ts)). The restore checks both tag peel and per-pin object closure. A disposable missing-blob Git probe confirmed `git rev-list --objects HEAD` exits nonzero for a missing blob, rather than silently proving an incomplete destination closure. Later destination drift is separate from historical custody.
- The moved-vault resolution now uses the receipt's capture-path archive ID under the **current** destination parent ([`vault.ts:88-146`](/archive/src/custody/vault.ts)); this addresses the earlier review's moved-archive concern. The permission/TOCTOU issue above remains.

## Cross-references

- [Custody implementation brief](/design/archive-migration/brief0.gpt6sol.md): full-inventory, explicit split-loss admission, private bundle, and independent verification requirements tested here.
- [Accepted direction](/design/archive-toolkit/direction0.gpt6astra.md): authorizes atomic receipt/pin transaction and separate source/read-only versus destination/write permissions.
- [Earlier core review](/design/archive-toolkit/core-review0.glm53.md): codec provenance, stash mapping, and bundle-head validation were fixed since its checkpoint and are not duplicated as current issues.
- [Luna source acquisition review](/design/archive-toolkit/safety-review0.gpt6luna.md): four complementary release problems, especially root aliasing and symlink/filter execution before the stage boundary.
