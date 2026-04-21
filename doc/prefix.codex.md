# Prefix Codex (Implementation-Forward Draft)

This doc translates [`ARCHITECTURE.md`](/ARCHITECTURE.md) into concrete,
incremental implementation slices.

It starts with one pilot domain: GET_URLS.

Reference history:

- [`doc/pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md)
- [`doc/intent-prefix-system.md`](/doc/intent-prefix-system.md)
- [`tasks/compfuzor/vars_get_urls.tasks`](/tasks/compfuzor/vars_get_urls.tasks)
- [`tasks/compfuzor/fs_get_urls.tasks`](/tasks/compfuzor/fs_get_urls.tasks)
- [`tasks/compfuzor/vars_kernel.tasks`](/tasks/compfuzor/vars_kernel.tasks)
- [`zswap.etc.pb`](/zswap.etc.pb)

## Why this codex exists

The architecture vocabulary is now clearer (`kind`, `origin`, `phase`, `role`,
`apply`, `effect`), but migration work still needs a practical sequence.

This codex is that sequence:

- pick one domain
- split by intent (foundation vs synthesis vs execution)
- preserve compatibility while introducing explicit handoff shapes

## Pilot target: GET_URLS

Current state:

- `vars_get_urls.tasks` injects a generated helper script (`get-urls.sh`) into
  `BINS`
- `fs_get_urls.tasks` applies host side effects (`get_url`, `.url` files)
- no explicit normalized spec record exists between these pieces

Desired state:

- one explicit normalized GET_URLS spec
- synthesis isolated from foundation
- execution consuming explicit spec records, not ad hoc shape checks

## Facet mapping for sample decomposition

| Piece | kind | origin | phase | role | apply | effect |
|---|---|---|---|---|---|---|
| `vars_get_urls.tasks` (retained, reduced) | `kind:vars` | `origin:task-file` | `phase:compile.foundation` | `role:foundation` | `apply:get-urls` | `effect:none` |
| `fn_get_urls.tasks` (new) | `kind:fn` | `origin:task-file` | `phase:compile.transform` | `role:transform` | `apply:get-urls` | `effect:none` |
| `gen_get_urls.tasks` (new) | `kind:syn` | `origin:task-file` | `phase:compile.synthesis` | `role:synthesis` | `apply:get-urls` | `effect:none` |
| `_syn_get_urls` (new record) | `kind:syn` + `record:_syn_get_urls` | `origin:fact-key` | `phase:compile.synthesis` | `role:synthesis` + `role:handoff` | `apply:get-urls` | `effect:none` |
| `fs_get_urls.tasks` (retained, narrowed) | `kind:fs` | `origin:task-file` | `phase:fs-apply` | `role:execution` | `apply:get-urls` | `effect:host.fs` |

## Concrete decomposition plan

### Slice 1: add explicit transform output

Create `fn_get_urls.tasks` to normalize `GET_URLS` into a stable internal spec.

Recommended outputs:

- `norm_get_urls`: normalized list of mappings
- `spec_get_urls`: ordered records with resolved `url`, `dest`, ownership,
  certificate policy, and source metadata

Compatibility rule:

- if normalized facts are absent, downstream tasks may fall back to existing
  `GET_URLS` behavior during migration

### Slice 2: move synthesis out of vars

Move generated helper script assembly from `vars_get_urls.tasks` into
`gen_get_urls.tasks`.

`gen_get_urls.tasks` should:

- derive helper bin payload from `spec_get_urls`
- synthesize merge payload (`syn_get_urls` and/or `_syn_get_urls`)
- merge into canonical artifacts (`BINS`) in one explicit merge step

`vars_get_urls.tasks` should remain only foundation/contract setup.

### Slice 3: narrow execution task

Update `fs_get_urls.tasks` to consume `spec_get_urls` (or `_syn_get_urls`) as the
primary input.

Execution behavior remains unchanged:

- fetch URLs to destination files
- write sibling `.url` marker files

But intent is now explicit: execution only, no synthesis.

### Slice 4: wire include order intentionally

Ensure `tasks/compfuzor.includes` imports in compile order:

- `vars_get_urls.tasks`
- `fn_get_urls.tasks`
- `gen_get_urls.tasks`

Then keep `fs_get_urls.tasks` in filesystem apply.

## Sample record shape (draft)

```yaml
_syn_get_urls:
  apply: get-urls
  entries:
    - url: "https://example.invalid/a.tar.gz"
      dest: "{{SRC}}/a.tar.gz"
      owner: "{{OWNER|default(omit)}}"
      group: "{{GROUP|default(omit)}}"
      validate_certs: true
```

This is still `kind:syn`; the `_syn_*` shape is record metadata, not a new kind.

## Guardrails for this pilot

- do not change host-side semantics in the first pass
- preserve `GET_URLS_BYPASS` behavior exactly
- keep fallback compatibility until at least one additional domain adopts the
  same pattern
- prefer one explicit merge per synthesized artifact target

## What this validates

If GET_URLS migration works cleanly, we can replicate the same decomposition
pattern for neighboring domains (`CONFIG`, `SYSTEMD`, archive download helpers)
without re-arguing taxonomy each time.

That is the main value of this codex: a repeatable, implementation-forward
template grounded in real tasks.

## Facet mapping for second sample decomposition (Kernel/Zswap)

Pilot input shape from [`zswap.etc.pb`](/zswap.etc.pb):

- `KERNEL_MODULES.zswap.params.*` supplies module parameter intent
- same subsystem also supports `KERNEL_SYSCTL` and `KERNEL_SYSFS`

| Piece | kind | origin | phase | role | apply | effect |
|---|---|---|---|---|---|---|
| `zswap.etc.pb` contract payload | `kind:raw` | `origin:task-file` | `phase:compile.foundation` | `role:foundation` | `apply:kernel` | `effect:none` |
| `vars_kernel.tasks` (current mixed form) | `kind:vars` | `origin:task-file` | `phase:compile.foundation` + `phase:compile.transform` + `phase:compile.synthesis` | `role:foundation` + `role:transform` + `role:synthesis` | `apply:kernel` | `effect:none` |
| `fn_kernel.tasks` (proposed split) | `kind:fn` | `origin:task-file` | `phase:compile.transform` | `role:transform` | `apply:kernel` | `effect:none` |
| `gen_kernel.tasks` (proposed split) | `kind:syn` | `origin:task-file` | `phase:compile.synthesis` | `role:synthesis` | `apply:kernel` | `effect:none` |
| `_syn_kernel` / `_syn_kernel_modules` / `_syn_kernel_sysctl` / `_syn_kernel_sysfs` (proposed records) | `kind:syn` + `record:_syn_kernel*` | `origin:fact-key` | `phase:compile.synthesis` | `role:synthesis` + `role:handoff` | `apply:kernel` | `effect:none` |
| `bins_run.tasks` + `files/kernel/install*.sh` apply path | `kind:bins` | `origin:task-file` | `phase:extras-apply` | `role:execution` | `apply:kernel` | `effect:host.fs` + `effect:host.kernel` |
| `kernel_modules.tasks` legacy path | `kind:fs` | `origin:task-file` | `phase:extras-apply` | `role:execution` | `apply:kernel` | `effect:host.fs` |

## Concrete decomposition plan (Kernel/Zswap)

### Slice 1: reduce `vars_kernel` to foundation-only

Keep only contract checks and top-level defaults in
[`tasks/compfuzor/vars_kernel.tasks`](/tasks/compfuzor/vars_kernel.tasks).

Move domain-table derivation out of `vars_*` so foundation stays small and
predictable.

### Slice 2: introduce `fn_kernel.tasks` for normalized spec outputs

Create explicit transform outputs:

- `norm_kernel_modules`, `norm_kernel_sysctl`, `norm_kernel_sysfs`
- `spec_kernel_domains` (ordered active domain table)
- `spec_kernel_bins` and `spec_kernel_env` from that single table

This preserves the good current design choice (one ordered domain table) while
placing it in `kind:fn`.

### Slice 3: introduce `gen_kernel.tasks` for synthesis records and merges

Move artifact synthesis and merge operations here:

- JSON entries for `ETC_FILES`
- build/install script entries for `BINS`
- env pointer facts (`KERNEL_*_JSON`, aggregate script lists)

Generate `_syn_kernel*` records before merging into canonical globals, so
execution phases can consume explicit handoff facts.

### Slice 4: keep execution stable, then narrow it

First pass: keep `bins_run.tasks` and existing `files/kernel/install*.sh`
behavior unchanged.

Second pass: have execution consume synthesized kernel records directly (instead
of depending on implicit global merges only), while preserving current install
semantics.

### Slice 5: define coexistence with legacy `kernel_modules.tasks`

For migration safety, document and enforce one rule:

- if `_syn_kernel*` exists, prefer synthesized path
- if absent, allow legacy `MODULES`/`kernel_modules.tasks` path

Then remove the legacy path after at least one full subsystem conversion (zswap
is the best first candidate).

## Appendix A: Document map and next-doc focus

This appendix is the current recommendation for where each kind of content
belongs while docs are being unified.

| Document | Current role | Status | Recommendation |
|---|---|---|---|
| [`/ARCHITECTURE.md`](/ARCHITECTURE.md) | architecture contracts and invariants | active | keep as canonical contract source (`phase/role/effect`, activation, lifecycle) |
| [`/doc/prefix.codex.md`](/doc/prefix.codex.md) | implementation-forward decomposition and migration examples | active working head for migration detail | capture new decomposition experiments and table demos here |
| [`/doc/pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md) | historical memo with useful narrative and early taxonomy | needs overhaul | fold into architecture terminology and lifecycle/activation contract |
| [`/doc/intent-prefix-system.md`](/doc/intent-prefix-system.md) | historical intent-prefix writeup | reference only | mine for ideas, but do not extend as primary source |

Recommended direction for the next push:

- use [`/ARCHITECTURE.md`](/ARCHITECTURE.md) for normative contracts
- use [`/doc/prefix.codex.md`](/doc/prefix.codex.md) for concrete domain plans
- rewrite [`/doc/pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md) to align with `phase/role/effect` and then either archive or replace the older intent memo

## Appendix B: Split review (ARCH vs memo)

What is good in the current split:

- architecture stays concise and contract-like
- codex carries domain-by-domain migration detail
- memos preserve design history and rationale

What needs improvement:

- terminology drift still exists across docs (`stage/class/side-effect` vs
  `phase/role/effect`)
- lifecycle contract is not yet uniformly documented in one place
- merge precedence and activation semantics are not yet expressed as explicit
  per-domain contracts

## Appendix C: Terminology unification map

Use these names as canonical in new/updated docs:

| Legacy term | Canonical term | Notes |
|---|---|---|
| `stage` | `phase` | use `phase:*` everywhere |
| `class` | `role` | behavior/responsibility tags |
| `side-effect` | `effect` | `none`, `host.fs`, `host.repo`, `host.kernel`, `network` |
| envelope taxonomy | `record` facet on kind | `_syn_<domain>` remains `kind:syn` |

## Appendix D: Domain lifecycle contract (draft)

Current lifecycle for each domain:

`raw -> norm -> spec -> syn -> apply`

| Lifecycle step | Producer kind | Required output shape | Expected phase | Effect allowed |
|---|---|---|---|---|
| `raw` | external input / playbook | `<DOMAIN>` inputs | `phase:compile.foundation` (entry) | `none` |
| `norm` | `kind:fn` (or temporary `kind:vars` during migration) | `norm_<domain>` | `phase:compile.transform` | `none` |
| `spec` | `kind:fn` | `spec_<domain>` (ordered, explicit contract records) | `phase:compile.transform` | `none` |
| `syn` | `kind:syn` (`gen_*`) | `_syn_<domain>` and optional `syn_<domain>` helpers | `phase:compile.synthesis` | `none` |
| `apply` | execution kinds (`repo`, `fs`, `bins`, extras) | host-side changes | `phase:*‑apply` | host/network effects as needed |

Lifecycle authoring guidance:

- prefer `spec_<domain>` as normative transform output
- `_syn_<domain>` is handoff metadata for synthesized/apply-facing payloads
- allow temporary direct `raw -> apply` fallback only while migrating a domain

### GET_URLS full lifecycle breakdown

| Step | Lifecycle | Producer | Input | Output | Phase | Role | Effect |
|---|---|---|---|---|---|---|---|
| 1 | `raw` | playbook (`GET_URLS`) | user-declared strings/mappings | `GET_URLS` | `phase:compile.foundation` | `role:foundation` | `effect:none` |
| 2 | `norm` | `fn_get_urls.tasks` | `GET_URLS` | `norm_get_urls` | `phase:compile.transform` | `role:transform` | `effect:none` |
| 3 | `spec` | `fn_get_urls.tasks` | `norm_get_urls` | `spec_get_urls` | `phase:compile.transform` | `role:transform` | `effect:none` |
| 4 | `syn` | `gen_get_urls.tasks` | `spec_get_urls` | `_syn_get_urls`, `syn_get_urls`, merged `BINS` entries | `phase:compile.synthesis` | `role:synthesis` + `role:handoff` | `effect:none` |
| 5 | `apply` | `fs_get_urls.tasks` | `spec_get_urls` or `_syn_get_urls.entries` | downloaded files + `.url` sidecars | `phase:fs-apply` | `role:execution` | `effect:host.fs` + `effect:network` |

## Appendix E: `_syn_<domain>` minimum handoff record schema

Minimum schema (old bullet now formalized):

```yaml
_syn_<domain>:
  schema: "compfuzor.syn.v1"
  domain: "<domain>"
  phase: "compile.synthesis"
  source:
    kind: "syn"
    producer: "gen_<domain>.tasks"
    from_spec: "spec_<domain>"
  apply: "<domain or target family>"
  entries: []
  meta:
    generated_at: "<optional timestamp>"
    notes: []
```

Minimum required keys:

- `schema`
- `domain`
- `source.producer`
- `apply`
- `entries`

Notes:

- this is still `kind:syn`; record shape does not define a new kind
- domain-specific entry payloads are allowed, but the outer scaffold is stable

## Appendix F: Domain activation, status, and trace facts

Per-domain activation contract (already captured in architecture) should be
paired with optional status and trace facts.

| Fact | Purpose |
|---|---|
| `<DOMAIN>_REQUESTED` | input exists and is non-empty |
| `<DOMAIN>_BYPASSED` | effective bypass state |
| `<DOMAIN>_VALID` | contract validation result |
| `<DOMAIN>_ACTIVE` | execution gate (`requested and not bypassed and valid`) |
| `<DOMAIN>_STATUS` | diagnostic mapping (`requested`, `bypassed`, `valid`, `active`, `reasons`) |
| `_trace_<domain>` | optional trace payload with lifecycle snapshots |

Trace fact suggestion:

```yaml
_trace_get_urls:
  lifecycle:
    raw: true
    norm: true
    spec: true
    syn: true
    apply: false
  refs:
    norm: norm_get_urls
    spec: spec_get_urls
    syn: _syn_get_urls
```

## Appendix G: Merge policy recommendations (configurable)

Goal: allow global defaults and per-domain overrides without losing
predictability.

Default recommendation (can be overridden):

- `user > existing-global > synthesized`

This default protects user intent and avoids synthesized data unexpectedly
overwriting existing explicit state.

Suggested config model:

```yaml
MERGE_POLICY_DEFAULT: user-existing-syn
MERGE_POLICY_DOMAIN:
  get_urls:
    BINS: user-existing-syn
    ENV: user-existing-syn
  kernel:
    BINS: user-existing-syn
    ETC_FILES: user-existing-syn
```

Supported strategies (draft):

- `user-existing-syn`
- `user-syn-existing`
- `existing-user-syn`
- `syn-user-existing`
- `append-dedup` (list-oriented)

Hard part acknowledgment:

- merge semantics differ by artifact type (mapping vs ordered list)
- per-domain, per-artifact strategy is likely needed, not one global switch

## Appendix H: Demo tables (GET_URLS + KERNEL/ZSWAP)

### H1. Producer -> artifact -> consumer lineage

| Domain | Producer | Artifact | Consumer | Lifecycle | Phase |
|---|---|---|---|---|---|
| `get_urls` | `fn_get_urls.tasks` | `spec_get_urls` | `gen_get_urls.tasks`, `fs_get_urls.tasks` | `spec` | `compile.transform` |
| `get_urls` | `gen_get_urls.tasks` | `_syn_get_urls` | `fs_get_urls.tasks` | `syn` | `compile.synthesis` |
| `kernel` | `fn_kernel.tasks` | `spec_kernel_domains`, `spec_kernel_bins` | `gen_kernel.tasks` | `spec` | `compile.transform` |
| `kernel` | `gen_kernel.tasks` | `_syn_kernel*` | kernel apply bins (`install*.sh`) | `syn` | `compile.synthesis` |

### H2. Artifact ownership

| Artifact | Authoritative producer | Allowed mutators | Forbidden writers |
|---|---|---|---|
| `spec_get_urls` | `fn_get_urls.tasks` | none (except migration shims) | apply tasks, playbooks |
| `_syn_get_urls` | `gen_get_urls.tasks` | none | `vars_*`, apply tasks |
| `spec_kernel_domains` | `fn_kernel.tasks` | none (except migration shims) | apply tasks |
| `_syn_kernel*` | `gen_kernel.tasks` | none | `vars_*`, apply tasks |

### H3. Activation and gating

| Domain | REQUESTED rule | BYPASSED rule | VALID rule | ACTIVE gate |
|---|---|---|---|---|
| `get_urls` | `GET_URLS|arrayitize|length > 0` | `GET_URLS_BYPASS|default(false)|bool` | each entry resolves `url` and `dest` | requested and not bypassed and valid |
| `kernel` | any of `KERNEL_MODULES`, `KERNEL_SYSCTL`, `KERNEL_SYSFS` non-empty | `KERNEL_BYPASS|default(false)|bool` | contract checks in kernel validation task | requested and not bypassed and valid |

### H4. Phase entry/exit guarantees (informative examples)

| Phase | Entry expectation | Exit guarantee example |
|---|---|---|
| `compile.foundation` | raw inputs available | domain activation facts computed (`*_REQUESTED`, `*_ACTIVE`) |
| `compile.transform` | activation known | `spec_*` facts exist for active domains |
| `compile.synthesis` | `spec_*` facts exist | `_syn_*` records and global merge artifacts prepared |
| `fs-apply` / `extras-apply` | synthesis outputs available | host changes applied only for active domains |

### H5. Migration status snapshot

| Domain | Legacy path | Target path | Status |
|---|---|---|---|
| `get_urls` | `vars_get_urls` + inline parse in `fs_get_urls` | `vars` (reduced) -> `fn` -> `gen` -> `fs` | in progress |
| `kernel/zswap` | mixed `vars_kernel` synthesis + legacy `kernel_modules.tasks` | `vars` (reduced) -> `fn_kernel` -> `gen_kernel` -> bins apply | in progress |

## Appendix I: Mutation authority guidance (draft)

These are recommendations, not hard prohibitions yet:

- `vars_*`: contract checks, defaults, activation facts only
- `fn_*`: produce `norm_*` and `spec_*`; do not mutate global apply artifacts
- `gen_*`: produce `_syn_*` and perform explicit merges into global artifacts
- apply tasks: consume `spec_*`/`_syn_*`; do not redefine compile-phase facts

Allowed exceptions:

- temporary migration shims
- internal/scratch facts (`_tmp_*`) for short-lived computation

## Appendix J: Pending TODOs for memo remake

- TODO: failure/skip policy matrix
- TODO: legacy coexistence policy (low-priority; migrate forward pragmatically)
- TODO: phase entry/exit guarantees (normative version)
- TODO: verification contract
- TODO: naming registry/rules
