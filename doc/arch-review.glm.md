# arch.md Review

Assessment of [`doc/arch.md`](arch.md) as standalone implementation guidance
ahead of the GET_URLS pilot migration.

This review assumes [`doc/pipeline-and-intent-prefix-memo.md`](pipeline-and-intent-prefix-memo.md)
and [`doc/intent-prefix-system.md`](intent-prefix-system.md) will be retired and
[`doc/prefix.codex.md`](prefix.codex.md) will be dropped, making arch.md the
sole architecture document.

## What arch.md does well

The subsystem model (`SUBSYSTEM_META` + `SUBSYSTEM` containers) is a clean
abstraction over the existing flat-fact sprawl. The control-vs-artifact field
split, the lifecycle `raw -> probe? -> norm -> spec -> contrib? -> apply`,
and the phase vocabulary with entry/exit expectations give an implementor a
clear mental model. The worked examples demonstrate the target shape
convincingly.

The problems are all in the gap between that model and the code that exists
today.

## Gaps that block GET_URLS implementation

### G1. No migration path from flat facts to SUBSYSTEM containers

The entire document assumes `SUBSYSTEM.get_urls` exists. The current system
uses `GET_URLS` as a flat list, `GET_URLS_BYPASS` as a flat flag, and produces
flat `BINS` via `set_fact`.

There is no guidance on:

- who creates the `SUBSYSTEM` container -- is it `vars_get_urls.tasks`? a
  shared helper? the helper described in section 2?
- how flat input vars (`GET_URLS`) translate into container fields
- whether flat facts like `GET_URLS` continue to exist alongside the container
  during migration, or get replaced immediately
- what the helper actually is -- a reusable task file? a filter plugin? an
  include with `vars:`?

Section 2 says "the architecture assumes a helper that resolves control-plane
state and creates runtime subsystem objects" and lists six steps. But it never
says where the helper lives, what it is called, or how you invoke it for one
subsystem versus another.

### G2. Input format contract is undefined

`GET_URLS` accepts three shapes in the wild:

- bare string: `GET_URLS: "https://...ripgrep_{{version}}_amd64.deb"` (ripgrep.opt.pb)
- list of strings: `GET_URLS: ["https://...", "https://..."]`
- list of mappings: `GET_URLS: [{url: "...", dest: "..."}]` (debinst-kexec.srv.pb)

Arch.md shows what `spec` looks like after normalization but never specifies:

- what `raw` looks like for any subsystem
- what normalization must handle (string coersion, default dest resolution,
  basename extraction)
- what the input schema validation rules are

Without this, an implementor cannot write `fn_get_urls.tasks` because they
don't know what they're normalizing from.

### G3. `norm` vs `spec` distinction is vague

The doc says `norm` is "normalized values with ambiguity removed" and `spec` is
"authoritative subsystem contract." For GET_URLS these would be nearly
identical -- a list of mappings with url/dest resolved.

When should they differ? Is `norm` always required before `spec`? Can you skip
`norm` and go straight to `spec`? The kernel example also has both but doesn't
explain the difference. An implementor cannot determine what to put in each
field.

### G4. `contrib` schema is unspecified

The GET_URLS example shows:

```yaml
contrib:
  BINS:
    - name: get-urls.sh
```

But:

- what are the valid artifact families under `contrib`? (`BINS`, `ETC_FILES`,
  `ENV`, `PKGS` -- all appear in `vars_kernel.tasks` but are never enumerated)
- can a subsystem contribute to multiple families simultaneously?
- how does the shape inside `contrib.BINS` relate to the shape of the global
  `BINS` list?
- is `contrib` always a dict keyed by artifact family, or can it take other
  shapes?

The TODO at line 747 acknowledges this ("exact contrib schema conventions for
major shared artifact families") but it is a blocker for writing `gen_*` tasks.

### G5. Shared artifact merge mechanics are hand-wavy

Section 5 says "each active subsystem produces explicit contribution fragments"
and "shared synthesis aggregates those fragments and resolves final precedence."

But:

- who aggregates? one `gen_*` task per subsystem? a single aggregation pass?
- what if two subsystems contribute a bin with the same `name`?
- the merge strategies (`user-existing-syn`, etc.) are listed but there is no
  guidance on which to use when or how the system selects one at runtime
- the `MERGE_POLICY_SUBSYSTEM` example shows config-driven selection but
  doesn't explain how it gets consulted during synthesis

### G6. Include ordering for split tasks is not concrete

The codex's four-slice pattern was: `vars_*` -> `fn_*` -> `gen_*` -> `fs_*`.
Arch.md lists compile subphases but never shows:

- whether `fn_*` tasks go after all `vars_*` tasks or can be interleaved
- whether `gen_*` ordering between subsystems matters
- the concrete include sequence in `compfuzor.includes` that produces correct
  phase ordering

An implementor needs to know where in the includes file to insert new split
tasks. The phase table gives the conceptual order but not the mechanical
placement.

### G7. The kernel task contradicts the model

[`tasks/compfuzor/vars_kernel.tasks`](/tasks/compfuzor/vars_kernel.tasks) is
the newest and most carefully designed task file. It does validation, builds an
ordered domain table, and directly merges into `ETC_FILES`, `BINS`, `ENV`,
`PKGS` -- all in one file, all in what arch.md calls `compile.foundation`.

Arch.md says `vars_*` should only do validation/defaults/activity and `gen_*`
should do merges. But the kernel task explicitly chose to do everything in one
step with a "data philosophy" header defending that choice.

The doc should either:

- acknowledge this pattern and explain when a single-file approach is
  acceptable vs when splitting is required, or
- explain why the kernel task should eventually split and what the migration
  path looks like

Right now an implementor sees a contradiction between the architecture doc and
the best-designed existing task file with no resolution.

## Gaps that block general implementation

### G8. Shared artifact entry shapes are undocumented

`BINS` entries in the wild have fields: `name`, `run`, `generated`, `src`,
`basedir`, `link`, `dest`, `global`, `delay`. Two patterns exist: inline
`generated` shell scripts (get_urls) and `src` references to external files
(kernel).

`ETC_FILES` entries in the wild have fields: `name`, `content`, `dest`,
`line`, `regexp`, `create`. At least two shapes: file-copy entries and
lineinfile entries.

Arch.md mentions these as shared artifacts but never specifies their entry
schemas. An implementor cannot know what to put in `contrib.BINS` without
knowing what a valid BINS entry looks like.

### G9. Playbook var to subsystem mapping is unspecified

`GET_URLS` is a playbook-level var. `SUBSYSTEM.get_urls` is a runtime
container. The mapping between them is never shown.

This is especially unclear for kernel, where `KERNEL_MODULES`,
`KERNEL_SYSCTL`, `KERNEL_SYSFS` are three separate playbook vars that feed
into multiple subsystem types (`kernel_modprobe`, `kernel_sysctl`,
`kernel_sysfs`) plus an orchestrator (`kernel_all`).

The doc needs to show: for each subsystem type, what playbook vars trigger it,
what the mapping logic is, and whether the helper does this mapping or the
`vars_*` task does.

### G10. The "generated" vs "src" BINS pattern is unexplained

`vars_get_urls.tasks` puts a shell script inline in `generated`. The current
`fs_get_urls.tasks` uses `get_url` module directly. `vars_kernel.tasks`
references external script files via `src` pointing into `files/kernel/`.

Both produce `BINS` entries. The doc doesn't explain:

- when to use inline `generated` vs external `src`
- how `generated` scripts get materialized at apply time
- what the lifecycle of a `BINS` entry is (declared in compile, written when?)

### G11. BYPASS resolution in practice

Section 7 defines the bypass resolution rules abstractly, but never shows how
existing playbook BYPASS vars (`GET_URLS_BYPASS`, `KERNEL_BYPASS`) feed into
`SUBSYSTEM.<name>.bypassed`. The helper contract says "resolve effective bypass
vars from `SUBSYSTEM_META.<id>.bypass_vars`" but doesn't show the lookup logic
for a concrete case.

## Minor issues

- The mermaid diagram in section 1 shows `SUBSYSTEM_META` -> `SUBSYSTEM` but
  doesn't show the helper or the compile subphases. It's a useful overview but
  doesn't match the detail level of the rest of the doc.

- Section 4 "Transport forms" explains when to use envelopes vs subsystem
  fields, but the guidance is abstract. A concrete rule per subsystem example
  would help.

- The "Naming rules" section says "prefer `SUBSYSTEM.get_urls.spec`" but
  doesn't address what happens to existing facts like `spec_get_urls` that
  other task files may already reference during migration.

## Recommended priority order for closing gaps

1. **G2 + G9** -- define input contract and playbook-var-to-subsystem mapping
   (without this, nobody can write `vars_get_urls.tasks`)
2. **G1** -- specify the helper: what it is, where it lives, how it's called
3. **G8** -- document `BINS` and `ETC_FILES` entry schemas
4. **G3 + G4** -- clarify norm/spec distinction and contrib schema
5. **G7** -- resolve the kernel task contradiction with explicit guidance on
   when single-file is acceptable
6. **G5 + G6** -- concrete merge mechanics and include ordering
7. **G10 + G11** -- BINS patterns and BYPASS resolution examples
