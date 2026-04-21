# Pipeline and Prefix Memo (Overhaul Draft)

This memo is the implementation-facing companion to [`/ARCHITECTURE.md`](/ARCHITECTURE.md).

It translates architecture contracts into practical authoring guidance,
decomposition patterns, and migration direction.

## Status and role

- This memo is active and intended to be revised during migration work.
- Architecture invariants stay in [`/ARCHITECTURE.md`](/ARCHITECTURE.md).
- Domain decomposition slices live in [`/doc/prefix.codex.md`](/doc/prefix.codex.md).

## Canonical terminology

Use these terms in new docs and updates:

| Legacy term | Canonical term |
|---|---|
| `stage` | `phase` |
| `class` | `role` |
| `side-effect` | `effect` |

Do not introduce a separate envelope taxonomy. A handoff key like
`_syn_<domain>` is still `kind:syn` with `record` metadata.

## Core dimensions

Compfuzor modeling uses two dimensions:

- `phase` (when work runs)
- facets (`kind`, `record`, `origin`, `role`, `apply`, `effect`) for what it is

## Phase vocabulary and mapping

Current phase names:

- `phase:compile`
- `phase:user-context`
- `phase:repo-apply`
- `phase:fs-apply`
- `phase:extras-apply`
- `phase:post-run`

Nested compile names are preferred when useful:

- `phase:compile.foundation`
- `phase:compile.transform`
- `phase:compile.synthesis`

Informative mapping to current include flow in
[`/tasks/compfuzor.includes`](/tasks/compfuzor.includes):

| Include region | Recommended phase label |
|---|---|
| vars/import pre-work | `phase:compile.*` |
| user context import | `phase:user-context` |
| repo imports | `phase:repo-apply` |
| fs/bins/links imports | `phase:fs-apply` |
| apt/pkgs/kernel/etc imports | `phase:extras-apply` |
| delayed links/thunks | `phase:post-run` |

## Domain lifecycle contract

Current lifecycle contract:

`raw -> norm -> spec -> syn -> apply`

| Step | Producer | Required output | Phase | Effect |
|---|---|---|---|---|
| `raw` | playbook/input | domain input vars | `compile.foundation` entry | `none` |
| `norm` | `fn_*` (temporary `vars_*` allowed during migration) | `norm_<domain>` | `compile.transform` | `none` |
| `spec` | `fn_*` | `spec_<domain>` (ordered, explicit records) | `compile.transform` | `none` |
| `syn` | `gen_*` | `_syn_<domain>` and merged artifacts | `compile.synthesis` | `none` |
| `apply` | execution tasks (`repo_*`, `fs_*`, `bins*`, extras) | host changes | `*-apply` | host/network |

Normative guidance:

- Prefer `spec_<domain>` as the primary transform contract.
- `_syn_<domain>` is synthesis handoff metadata for apply-facing payloads.
- Direct `raw -> apply` is migration-only fallback, not target design.

## Domain activation contract

Each domain should compute a shared activation contract in foundation:

- `<DOMAIN>_REQUESTED`
- `<DOMAIN>_BYPASSED`
- `<DOMAIN>_VALID`
- `<DOMAIN>_ACTIVE`

Where:

`<DOMAIN>_ACTIVE = <DOMAIN>_REQUESTED and not <DOMAIN>_BYPASSED and <DOMAIN>_VALID`

Optional but recommended:

- `<DOMAIN>_STATUS` mapping with `requested`, `bypassed`, `valid`, `active`,
  and `reasons`
- `_trace_<domain>` for lifecycle observability during migration

Execution rule:

- Compile transform/synthesis and apply tasks should gate on `<DOMAIN>_ACTIVE`.

## `_syn_<domain>` minimum handoff schema

Minimum stable scaffold:

```yaml
_syn_<domain>:
  schema: "compfuzor.syn.v1"
  domain: "<domain>"
  phase: "compile.synthesis"
  source:
    kind: "syn"
    producer: "gen_<domain>.tasks"
    from_spec: "spec_<domain>"
  apply: "<domain-or-target-family>"
  entries: []
```

Required keys:

- `schema`
- `domain`
- `source.producer`
- `apply`
- `entries`

## Authoring and mutation guidance

Recommended authority boundaries:

- `vars_*`: validate contract, set defaults, compute activation/status facts
- `fn_*`: emit `norm_*` and `spec_*`, avoid host effects
- `gen_*`: emit `_syn_*`, perform explicit merges into global artifacts
- apply tasks: consume `spec_*`/`_syn_*`, perform host effects only

These are recommendations; temporary migration shims are allowed.

## Merge policy recommendations

Default precedence recommendation:

- `user > existing-global > synthesized`

Rationale: preserve explicit user intent, avoid unexpected synthesis overwrite,
and keep existing state stable unless intentionally changed.

Suggested future config pattern:

```yaml
MERGE_POLICY_DEFAULT: user-existing-syn
MERGE_POLICY_DOMAIN:
  get_urls:
    BINS: user-existing-syn
  kernel:
    ETC_FILES: user-existing-syn
```

## Worked example: GET_URLS lifecycle

| Step | Producer | Input | Output | Phase | Role | Effect |
|---|---|---|---|---|---|---|
| raw | playbook | `GET_URLS` | `GET_URLS` | `compile.foundation` | `foundation` | `none` |
| norm | `fn_get_urls.tasks` | `GET_URLS` | `norm_get_urls` | `compile.transform` | `transform` | `none` |
| spec | `fn_get_urls.tasks` | `norm_get_urls` | `spec_get_urls` | `compile.transform` | `transform` | `none` |
| syn | `gen_get_urls.tasks` | `spec_get_urls` | `_syn_get_urls`, `BINS` merge payload | `compile.synthesis` | `synthesis` + `handoff` | `none` |
| apply | `fs_get_urls.tasks` | `spec_get_urls` or `_syn_get_urls.entries` | downloaded files + `.url` sidecars | `fs-apply` | `execution` | `host.fs` + `network` |

## Worked example: Kernel/Zswap lifecycle

| Step | Producer | Input | Output | Phase | Role | Effect |
|---|---|---|---|---|---|---|
| raw | playbook (`zswap.etc.pb`) | `KERNEL_MODULES`/`KERNEL_SYSCTL`/`KERNEL_SYSFS` | raw kernel vars | `compile.foundation` | `foundation` | `none` |
| norm/spec | `fn_kernel.tasks` (target split) | raw kernel vars | `norm_kernel_*`, `spec_kernel_*` | `compile.transform` | `transform` | `none` |
| syn | `gen_kernel.tasks` (target split) | `spec_kernel_*` | `_syn_kernel*`, merged `ETC_FILES`/`BINS` payloads | `compile.synthesis` | `synthesis` + `handoff` | `none` |
| apply | bins/install scripts + extras | synthesized kernel payloads | module/sysctl/sysfs host changes | `extras-apply` | `execution` | `host.fs` + `host.kernel` |

## Seams to retain from older intent docs

These remain useful and should stay visible:

- `gen_` filename prefix and `synthesis` concept are both intentional.
- config/get_urls/systemd remain key decomposition seams.
- `fn_multi` is allowed only when contract-driven and explicit.

`fn_multi` minimum bar:

- declared input schema
- deterministic output names
- no hidden side effects
- domain wrappers when generic shape hurts readability

## Success criteria

A contributor should be able to answer quickly:

- where does this logic belong by lifecycle step?
- what artifact should this task produce?
- what task type is allowed to merge this artifact?
- which phase is allowed to apply host-side changes?

## Pending items for the next revision

- TODO: failure/skip policy matrix
- TODO: legacy coexistence policy (migration-forward bias)
- TODO: normative phase entry/exit guarantees
- TODO: verification contract
- TODO: naming registry/rules
