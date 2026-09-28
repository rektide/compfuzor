---
type: Review
title: Core custody/recovery slice — independent safety review
description: Findings against archive/src/custody/{model,codec,errors}.ts and archive/src/recovery/{retry,transaction,git-ref-store}.ts, checked against the custody brief and accepted direction.
status: draft
generated: { by: model:glm53, at: 2026-09-27 }
sources:
  - id: brief
    resource: /design/archive-migration/brief0.gpt6sol.md
    title: Git custody implementation brief
  - id: direction
    resource: /design/archive-toolkit/direction0.gpt6astra.md
    title: Accepted toolkit direction
---

# Context

Focused review of the core data/transaction slice (receipt codec, pin mapping,
retry admission, atomic ref installation) against
[the brief](/design/archive-migration/brief0.gpt6sol.md) and
[the accepted direction](/design/archive-toolkit/direction0.gpt6astra.md).
Missing full apply/inventory/verifier is a known slice boundary, not a finding;
the Git env-contamination issue already being fixed is excluded. Real-Git
transaction behavior is covered by 19 passing tests
([`test/custody/transaction.test.ts`](/archive/test/custody/transaction.test.ts));
I re-derived the claims below by reading the code and ran a disposable probe
(`.test-agent/core-review-glm53/probe.ts`) to confirm acceptance/rejection
behavior — every ACCEPTED/rejected line below was executed against the actual
codec.

# Findings

## H1 — `refName` rejects two-component refs, breaking the `refs/stash` lane (codec.ts:76)

`refName` requires `name.split("/").length >= 3`. `refs/stash` — the canonical
stash ref and a first-class custody lane in the brief's mapping table — has two
components and is valid Git (`git check-ref-format refs/stash` → valid,
verified locally). Consequences, all fail-closed but lane-blocking:

- Inventory decode throws on any stash-bearing source:
  [`inventory/decode.ts:90`](/archive/src/custody/inventory/decode.ts) runs
  `refName(name)` over `for-each-ref` output, and
  [`inventory/probe.ts:670`](/archive/src/custody/inventory/probe.ts) expects
  `refs/stash` to appear there.
- No pin can name it: `pinRef` kinds `stash`/`other` validate `sourceName` via
  `refName` (codec.ts:168), so `sourceName: "refs/stash"` is unrepresentable;
  the receipt coverage loop (codec.ts:470-479) then makes any receipt covering
  a stash tip unparsable.

**Fix:** require the first component to be `refs` with a nonempty remainder
(one-level names stay rejected); keep all per-component rules. **Test:** a
receipt whose `source.refs` contains a `refs/stash` tip plus its `stash`-kind
pin round-trips through `parseReceipt`; a one-level name still fails.

## M2 — Candidate-pin provenance is not bound to the pinned OID or format (codec.ts:164-169, 413-421, 481-493)

For `reflog`-kind pins, `pinRef` only checks `sourceName` against
`/^(stash-older|reflog|dangling):[0-9a-f]{40}([0-9a-f]{24})?$/` — accepting
either hash length regardless of the receipt's `objectFormat` — and
`validateReceipt` validates `sourceName` only as `nonempty` (codec.ts:416).
The candidate loop checks candidates→pins, never pins→candidates. Probe
confirmed: a sha1 receipt with a pin `{sourceKind: "reflog", sourceName:
"reflog:<64-hex>", sourceOid: O("1"), ...}` — embedded OID of the wrong length
*and different from the pinned OID* — **passes `validateReceipt`**. A pin
over a candidate dispositioned `not-required` (with reason) also **passes**
(only `unclassified` is rejected, codec.ts:545). This corrupts the receipt's
core provenance claim ("stable pin identity is kind + full OID") while keeping
the deterministic mapping verifier-consistent.

**Fix (all inside `validateReceipt`'s per-pin loop):** for `reflog` kind,
decompose `sourceName`, require the embedded OID to be format-valid *and*
equal to `sourceOid`; reject any pin whose sourceName equals
`candidateIdentity(...)` of a `not-required` candidate. Optionally require
pin.sourceKind to agree with the candidate kind prefix. **Tests:** the two
probe cases above must throw; a correct `reflog:<sourceOid>` pin keeps passing.

## M3 — `bundle.verifiedHeads` is never cross-checked against pins (codec.ts:423-428)

The receipt's fresh-restore guarantee is only as good as the recorded bundle
heads, but nothing in `validateReceipt` requires the pins' OIDs (or the receipt
commit's objects) to be covered by `verifiedHeads`. Probe confirmed a receipt
with a branch pin whose OID appears nowhere in `verifiedHeads` is accepted. The
brief requires "exact bundle heads" so verification can prove closure; if that
check lives only in the future verifier, a minting bug produces receipts that
are parse-valid but unprovable. **Fix:** require every `pin.destinationOid` to
appear among `verifiedHeads` OIDs (heads are stage refs, so match by OID set).
**Test:** same probe case must throw; a receipt whose heads cover all pins
keeps passing.

## L4 — `destinationPreRefsSha256` is unverifiable summary state (codec.ts:405)

Unlike `destinationPreRefs` (exact map, compared by retry), this hash is never
recomputed against anything, so it is dead weight that can disagree with the
array it summarizes. Either define the canonical recipe (e.g.
`sha256(canonicalJson(sorted [name, oid] pairs) + "\n")`) and check it in
`validateReceipt`, or drop the field. Same treatment for the retry path:
duplicate names inside `destinationPreRefs` silently collapse through the
`Map` constructors (retry.ts:70-73) — reject duplicate names in
`validateReceipt`.

## L5 — Retry equality is array-order-sensitive; enumeration order is now load-bearing (retry.ts:46-48)

`same(plan.pins, receipt.pins)` and the source/baseline comparisons use
`canonicalJson`, which preserves array order. This is fail-closed (a reordered
fresh plan hard-stops the retry), but it makes deterministic enumeration of
pins/refs/index entries a correctness requirement of the future inventory
rather than a style preference. Either sort both sides canonically before
comparison or state the ordering contract at the `PlanV1`/`SourceInventory`
types. Relatedly, `sortedRefs` (retry.ts:11) uses `localeCompare` where
everything else compares codepoints — consistent within one process today, but
switching to the same `<` compare as `canonicalJson` removes a locale
dependency for free.

## L6 — Receipt-commit ↔ receipt-blob binding is caller discipline only (retry.ts:21-26, 65)

`approveSameInputRetry` checks `currentRefs.get(receiptRef) === receiptCommitOid`
but cannot check that the blob the caller parsed is actually
`<receiptCommitOid>:adoption.json`. The comment documents the contract, but the
seam is easy to cross (e.g. parsing bytes fetched by blob OID). Suggest a
helper — accept the receipt bytes and export the expected
`rev-parse <commit>:adoption.json` query, or take a small callback — so the
adapter closes it mechanically instead of by convention.

## L7 — Moved archives cannot ever verify; decide if that is v1 (codec.ts:121-137, 440-445)

`validateReceipt` binds `bundle.pathRelativeToDestinationParent` to
`sha256(identity.destinationRealpath)`, and the vault resolves under
`dirname(destinationRealpath)` — both captured at mint time. Moving dest+vault
together leaves verification resolving the *old* parent with the *old* hash
dir name; the immutable receipt cannot be updated. The brief's "a moved archive
needs its private vault moved with it" implies support this scheme cannot give.
Fails closed; fine to keep for v1, but record the decision (unsupported, or
verify against `--dest`-relative paths without the dest-hash component).

## Nits

- `pinRef` interpolates `sourceOid`/snapshot OIDs into the leaf without
  validating them (codec.ts:159, 163); safe inside `validateReceipt`
  (validated earlier), but the exported function should self-validate.
- `decideInstallation`/`requiredRefs` do O(n²) pair scans
  (transaction.ts:43-51, 107-115); thousands of reflog pins would crawl. Sort
  + neighbor check if candidate counts get large.
- `refName`'s 4096 limit counts UTF-16 units, not bytes (codec.ts:76); Git's
  limit is bytes, so multibyte refs over-reject near the boundary.

# Effect Schema vs the bespoke validator framework

`codec.ts` carries ~120 lines of combinator framework plus ~190 lines of field
tables (`record/shape/str/arr/...` codec.ts:174-295; `validateReceipt`
codec.ts:311-548; `reviewSchema` codec.ts:262-279). The installed
`effect@4.0.0-rc.118` ships `effect/Schema` (`Struct`, `brand`,
`onExposure`/`onExcessProperty: "error"`) which covers exactly this: unknown-
and missing-field rejection, branded outputs, accumulated path-bearing
diagnostics (today the first `invalid()` wins and the message often lacks the
JSON path the `at` parameter already computed). The real cost of the bespoke
framework is **double declaration**: every `model.ts` interface is
hand-mirrored in the validator tables and can drift silently.

Do **not** rewrite `validateReceipt` mid-slice — the tables are tested and the
byte-exact canonical round-trip (`parseReceipt`'s wire equality, codec.ts:563)
and format-parameterized OID checks would still be hand-rolled around Schema.
Proportionate adoption:

1. When the missing `PlanV1`/`Verification` parser is written (there is
   currently **no** codec entry point that validates plans at all —
   `approveSameInputRetry` only spot-checks schema/state/blockers and leans on
   canonical equality against a validated receipt for the rest), build it with
   `effect/Schema` in a sibling module instead of extending the framework.
2. Note that `model.ts:1` declares "No Effect dependency in the data layer" —
   adopting Schema in `custody/` revisits that boundary deliberately, in a
   dedicated slice, not as a drive-by.

# Checked and found sound

No action needed on: lane injectivity and prefix non-collision of
`encodeIdentity`/`pinRef` (length-prefixed hex components cannot collide or
D/F-conflict across or within lanes); HEAD/working-copy pin invariants and
content-addressed leaves; snapshot-parent/head binding; `.git`/`.jj` and
gitlink rejections in tree manifests; path-review manifest binding and
sensitive-path coverage; unclassified-candidate rejection; `requiredRefs`
duplicate/zero-OID/newline-injection guards (branded types correctly not
trusted); the `verify`+`create` transaction protocol with precheck and
in-transaction re-check (race tests, including real-Git ones, are strong);
retry's custody-ref discounting and original-baseline retention (the
plan-vs-receipt `destinationPreRefs` asymmetry is deliberate and correctly
commented); legacy `harvest/<label>/head|working-copy` namespace refusal;
vault-path lexical confinement; label/generation ref-component validation via
the injective `receiptRef` round-trip; failing wrapped as typed
`CustodyError`s throughout `git-ref-store`.

# Suggested tests (beyond the probe cases)

1. **Stash lane (H1):** receipt with `refs/stash` tip + `stash`-kind pin
   parses; `refs/notes/x`, two-component ref round-trip; one-level name fails.
2. **Provenance binding (M2):** inconsistent/mistyped reflog identities and
   pins over `not-required` candidates throw (probe cases promoted).
3. **Bundle-head coverage (M3):** pin OID missing from `verifiedHeads` throws.
4. **Baseline hygiene (L4):** duplicate `destinationPreRefs` names throw;
   (if kept) mismatched `destinationPreRefsSha256` throws.
5. **Retry ordering (L5):** permuted `plan.pins` — assert the chosen contract
   (sorted-compare passes, or document the hard stop).
6. **Legacy leaf D/F (transaction):** existing leaf
   `refs/heads/harvest/<label>/<generation>` (legacy branch literally named
   `g0`) blocks the generation via the generic prefix scan — one assertion
   locks in that interaction.
