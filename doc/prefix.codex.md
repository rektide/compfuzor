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
