---
type: OperatorGuide
title: Archive adoption custody — operator and library guide
description: Current local Git custody admission, review inputs, receipt verification and public library entry points; not retirement approval.
resource: /doc/archive-toolkit/custody.md
tags: [compfuzor, archive, adoption, git, jj, custody]
status: draft
generated: { by: model:gpt6sol, at: 2026-09-28 }
stale_after: 2026-11-28
sources:
  - id: implementation
    resource: /archive/src/index.ts
    title: Public library exports
  - id: contract
    resource: /archive/README.md
    title: Archive operator contract
  - id: brief
    resource: /design/archive-migration/brief0.gpt6sol.md
    title: Intended custody implementation brief
---

# Archive adoption custody

`adopt` takes custody of selected **local Git** objects and exact worktree
content from a standalone checkout in an existing jj-colocated archive.
`verify-adoption` independently tests that custody later, without needing the
source. This is a local custody operation, not deployment migration, backup of
runtime state, remote publication, or authorization to dispose of the source.
Existing-destination clean/dirty fixture tests pass; final independent safety
review is pending. Do **not** infer production signoff or full brief v1 support.
Stop all writers to both checkouts before planning and keep them stopped through
apply: fingerprint checks are not an atomic snapshot of a live repository.

## Admission boundary

- The destination must already be a healthy jj-colocated checkout. A missing
  destination blocks planning/apply. If you deliberately want to create one,
  run the **separate** `refresh` command after reviewing its behavior: it
  creates/adopts and mutates the selected checkout, and may fetch/reconcile.
  `adopt` itself does not clone, fetch, heal, or change either worktree.
- Detached HEAD, ordinary branches/tags (including annotated tags), named Git
  refs, reviewed dirty worktrees, and classified candidate tips are custody
  inputs. Local remote-tracking tips are a **local-only** baseline, not proof
  of server freshness or publication. The plan identifies what it can inspect
  and reports unknowns instead of treating them as empty.
- Tree/blob-tip refs, incomplete Git object closures, unmerged index, gitlinks/
  submodules, unsupported repository layouts or filters/LFS/smudging, and
  unprovable jj-only history block admission. A staged-index-only change with
  no synthetic worktree snapshot is also blocked: the tool cannot preserve
  that separate index state. A dirty snapshot gives **one** resulting tree;
  staged vs unstaged versions are not independently preserved. Ignored files,
  Git/jj internals and explicitly excluded untracked paths remain behind.
  Review reported blockers and `retirementUnresolved` rather than forcing them.
- Do not adopt sensitive content casually. Tracked sensitive paths cannot be
  omitted from committed history; reviewing local custody does **not** approve
  publication. Inspect names, modes, object IDs and classifications, not secret
  contents, in review files or console output.

## Plan, review, apply, verify

Use the source entry while developing in this checkout (`pnpm install` for CLI
dependencies); the committed `archive/repo-jj-archive.ts` is the **Node 26
single-file distribution bundle**, not the development entry point. Examples
use placeholders and must be run only against explicitly chosen disposable
fixtures or repositories cleared for this operation:

```sh
node archive/src/repo-jj-archive.ts adopt \
  --legacy /path/to/legacy --dest /path/to/existing-archive \
  --repo https://github.com/ORG/REPO --label NAME \
  --branch main --generation g0 --json
# Inspect plan.state, blockers, warnings, retirementUnresolved,
# source.candidates and exact path manifests before preparing review files.
node archive/src/repo-jj-archive.ts adopt \
  --legacy /path/to/legacy --dest /path/to/existing-archive \
  --repo https://github.com/ORG/REPO --label NAME \
  --branch main --generation g0 --dispositions /path/to/decisions.json \
  --path-review /path/to/review.json --apply --json
node archive/src/repo-jj-archive.ts verify-adoption \
  --dest /path/to/existing-archive --receipt refs/adopt/receipts/NAME/g0 --json
```

Optional `--legacy /path/to/legacy` on verify only adds source-drift diagnosis.
Do not run `--apply` simply because the plan process exited 0: a read-only
plan with `state: "blocked"` and explicit blockers can still exit 0. An apply
requires a fresh ready plan, rechecks its inputs, installs immutable custody
pins and a receipt ref, seals a private bundle beside the destination, then
verifies. A changed source or destination requires replanning. A successful
`--json` command prints exactly **one JSON line**; CLI failure has nonzero exit
and **empty stdout** (diagnostics on stderr). Verification failure does not
produce a successful JSON report on stdout. Preserve any failure evidence for
investigation, including private verification scratch if retained.

### Review inputs

`--exclude-from FILE` uses Git's `ls-files --exclude-from` patterns and
selects **only untracked** paths; the plan records excluded names and file
digest. It does not remove tracked content. `--dispositions FILE` is a JSON
object keyed by exact `kind:full-oid` identities found in
`plan.source.candidates` (`stash-older`, `reflog`, `dangling`). Values have
`disposition: "pin"` (optional string `reason`) or `disposition:
"not-required"` with a nonempty operator `reason`. For example, substituting
the **actual** candidate OID from the plan:

```json
{
  "dangling:<full-oid-from-plan>": {
    "disposition": "not-required",
    "reason": "Operator-confirmed disposable test commit, not wanted history"
  }
}
```

The placeholder above is illustrative, **not** valid input until replaced by
an actual SHA-1/SHA-256 OID. Do not classify unfamiliar history as disposable.
Unknown candidate keys are rejected. Candidate decisions are separate from
path privacy review.

`--path-review FILE` is an external JSON object with **exactly** `schema`,
`manifestSha256`, `included`, and `stagedVsUnstaged`. Do **not** include
`fileSha256`: the codec calculates it from the input bytes and adds it to the
recorded review. For a dirty snapshot use
`plan.proposedSnapshot.manifestSha256`; for clean HEAD use
`plan.headManifestSha256`. Copy each actual reviewed entry's `path`, `mode`
and `blobOid` from the corresponding plan manifest (`proposedSnapshot.paths`
or `source.head.treePaths`). Record a specific local-custody reason; this
example's placeholders are not blanket authorization:

```json
{
  "schema": "compfuzor.archive-path-review/v1",
  "manifestSha256": "<digest-from-plan>",
  "included": [
    {
      "path": "<exact-reviewed-path>",
      "mode": "<mode-from-manifest>",
      "blobOid": "<oid-from-manifest>",
      "classification": "credential",
      "decision": "local-custody-approved",
      "reason": "<specific reason for keeping these bytes locally, not publishing>"
    }
  ],
  "stagedVsUnstaged": null
}
```

Allowed classifications are `credential`, `runtime-state`, and
`other-sensitive`. For a dirty plan with
`proposedSnapshot.reviewRequirements.stagedVsUnstagedApprovalRequired: true`,
replace `null` with `{ "decision": "single-tree-approved", "reason": "<specific
reason why loss of the index/worktree split is acceptable>" }`. For a clean
HEAD review it **must** be null. If separate staged state matters, stop and
arrange separate custody instead of approving a single tree. Only include
actually reviewed paths; the plan/receipt checks exact manifest identity,
mode and blob OID and demands review of sensitive included paths.

## Receipt, vault and non-guarantees

The receipt at `refs/adopt/receipts/<label>/<generation>` names source tips,
pin refs, exact path manifests, locally observed baselines and a SHA-256-bound
private bundle. Verification rereads the receipt from the destination Git
store and checks pins, object closure, manifests, bundle checksum and a fresh
empty-repository restore independently of the source. It separately reports
source drift (if requested), destination drift and unresolved retirement items.
The bundle lives in `.compfuzor-adoptions/` beside the destination, **not**
inside its worktree or automatically in a remote. Move the destination and
its sibling private vault **together** if relocating the archive; verification
resolves the recorded vault subpath under the current destination parent.
Protect both artifacts and their access permissions. A cloned destination
without the vault does not provide this independent restore proof.

This proves custody of the selected Git data, **not** ignored runtime files,
`.jj` operation history, server publication, off-host backup, deployment
selection, or safe deletion of the legacy checkout. Never equate
`custodyVerified: true` with retirement readiness; evaluate every
`retirementUnresolved` item independently. No custody command publishes,
prunes, or deletes the source.

## Public library entry points

[`archive/src/index.ts`](/archive/src/index.ts) is the explicit library export
surface, with structured results rather than CLI presentation. Ordinary
repository/recovery helpers (`preflight`, `snapshot`, `fetchRemote`,
`refreshArchive`, `harvest`, `heal`, etc.) are Promise-based; `jj`/Git execution
is behind repository modules. Custody `planAdoption(input)` and
`applyAdoption(input)` instead return **Effect** values, as does
`loadDispositions(path)`: run them in an appropriate Effect runtime, not with
`await` alone. `verifyAdoption({ dest, receiptRef, legacy, scratchRoot },
{ signal })` and `readReceipt(dest, receiptRef, { signal })` return Promises.
The caller supplies an existing private `scratchRoot` outside both checkouts
for verification; the CLI chooses/cleans its own scratch on success. The
optional `AbortSignal` on these Promise verification APIs supports cancellation
of child work; the CLI arranges its own signal lifecycle. `AdoptInput`,
`PlanV1`, `ReceiptV1`, `Verification`, `PathReview` and `CustodyError` are
exported types/error surfaces. Do not mistake this mixed API for an all-Effect
library or a guaranteed stable external package API.

## Cross-references and review status

- [Operator CLI and Node 26 transport](/archive/README.md): launcher,
  distribution bundle, refresh safety and Ansible protocol.
- [Implementation direction](/design/archive-toolkit/direction0.gpt6astra.md)
  and [custody contracts](/design/archive-toolkit/custody-contracts0.gpt6sol.md):
  architectural intent and module boundaries, not a production certificate.
- [Custody implementation brief](/design/archive-migration/brief0.gpt6sol.md):
  larger intended v1; its absent-destination clone allowance is **not** the
  current implementation. Follow implemented blockers rather than assuming
  every brief feature is delivered.
- [Core safety review](/design/archive-toolkit/core-review0.glm53.md):
  historical findings; some corrections landed, but final independent review
  remains pending. No reviewer acceptance is implied here.
