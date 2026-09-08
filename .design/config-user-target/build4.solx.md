---
type: ArchitectureCheckpoint
title: Final consumer-config safety and integration review
description: Resolve canonical alias mutation, local-extra status, orchestrator identity, shared LINKS bundle, standards, and demo safety findings after the Zim migration.
resource: /.design/config-user-target/build4.solx.md
tags: [compfuzor, config, zim, mise, links, safety, verification]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
stale_after: 2026-10-08
sources:
  - id: migration-checkpoint
    resource: /.design/config-user-target/build3.solx.md
    title: Zim consumer migration and Mise block status
  - id: user-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
---

# Final consumer-config safety and integration review

## Outcome

The two independent spec gaps, the parent-reproduced ambient deployment bug,
the standards findings, and demo safety are resolved. The accepted CONFIGS
context and Zim/Mise architecture did not need another ownership model.

No live playbook, package manager, canonical `/opt` deployment, or real user
startup file was changed.

## Canonical alias-mutation invariant

Consumer mutation now checks physical recipe identity, not only the immediate
copy/link source:

- a bound glob input directory may not physically resolve to its canonical
  donor directory;
- a bound direct-file input may not name the canonical input entry through an
  aliased parent;
- a bound context output may not name the canonical output entry through an
  aliased parent.

Directory comparison follows the final directory symlink. File/output entry
comparison resolves physical parents but deliberately does **not** follow the
final consumer symlink. Therefore ordinary per-file donor links remain
replaceable/renameable and whole-link-to-copy or local assembly detachment still
works.

The check runs before context input put/toggle/remove/seed/refresh and before an
assembly apply. Preview/list/check/stdout remain read-only and may inspect an
aliased layout. Status reports `alias-hazard` input/output rows rather than
claiming the state is safely local. Focused tests prove put, direct-file put,
toggle, remove, and assembly cannot change donor entries through aliased parent
directories.

This is the one operation-specific donor-protection invariant; no receipt,
force gate, path sandbox, or permissions framework was added.

## Local-extra symlink status

Every extra local symlink is now followed for status classification:

- missing referent or a dangling producer chain: nonclean `dangling` (or
  `donor-missing` when the textual relationship is visible);
- directory/non-file referent: nonclean `non-file-referent`;
- inspection failure: `evaluation-error`;
- final regular file: accepted local input.

Enabled/disabled naming remains visible independently of referent health. The
toolkit still permits operators to create unusual or dangling links; status no
longer reports them healthy.

## Deployment-rooted orchestrators

Generated action compositors and the generated `status.sh` now derive `DIR`
from their own executable before loading `env.export` or dispatching children.
Leaf behavior remains unchanged unless it is one of these explicit
orchestrator roles.

Verified cases:

- valid foreign deployment containing sentinel children: intended children run,
  foreign sentinels do not;
- missing foreign `DIR`: generated compositor still runs its own body/children;
- generated status orchestrator: intended reporter runs and returns drift,
  never a silent false-clean;
- actual rendered Zim `install-user.sh` and `status.sh`: both work with a valid
  foreign or missing ambient `DIR`.

## Shared LINKS runtime bundle

[`runtime_bundles.py`](/library/filter_plugins/runtime_bundles.py) is the one
descriptor source for:

- delivery-only: `links/delivery.ts`;
- full manager: stable `links.ts` facade, `links/links.ts`, and
  `links/delivery.ts`;
- required `bin/links` module directory.

The config context compiler consumes the delivery bundle. `gen_links.tasks` and
the Zim host consume the full bundle. BINS keyed merging still deduplicates a
deployment needing both. `zim-registry.sh` now invokes the stable
`bin/links.ts` facade rather than the internal module path.

## Standards and user documentation

- [`library/README.md`](/library/README.md) now documents the actual
  `config_context_compile` signature/None/undefined behavior, the host-aware
  `zim_fragment(..., host=False)` signature/layouts, both runtime-bundle
  filters, and their module map entries.
- [`doc/subsys.md`](/doc/subsys.md#declared-links-and-shared-link-delivery)
  distinguishes `DIR/links.json` declaration ownership from permissive CONFIGS
  explicit delivery sharing the same atomic link primitive. It records that
  user LINKS never sudo while system routing retains auto/always/never.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) now starts the Zim
  workflow with full `install-user.sh`, distinguishes it from daily
  config-only assembly, states that the updated playbook must be rendered and
  has not been live-deployed, records donor readability requirements, and
  explains alias-hazard status.

No per-variant generation knob is claimed. Generic BINS tombstones exist, but a
specific context-variant policy interface was not added or verified.

## Demo allocation and preserved proof

`COMPFUZOR_KEEP_ZIM_DEMO` no longer recursively deletes its requested path:

- truthy shorthand allocates a fresh unique directory below
  `.test-agent/config-contexts/`;
- an explicit path is created if absent, accepted if empty, and refused if
  nonempty without deleting anything.

A retained demo writes its own `README.md`, harmless stub-controller
description, donor/user path map, and executable `user-one.sh` / `user-two.sh`
environment wrappers. Those wrappers run generated tools without sourcing a
live profile.

Current preserved proof:

```text
/home/rektide/src/compfuzor/.test-agent/config-contexts/final-demo.hVQQs0
```

Examples:

```bash
demo=/home/rektide/src/compfuzor/.test-agent/config-contexts/final-demo.hVQQs0
"$demo/user-one.sh" "$demo/zim host with spaces/bin/status.sh"
"$demo/user-one.sh" "$demo/zim host with spaces/bin/config-user.sh" --check zimrc
"$demo/user-one.sh" "$demo/zim host with spaces/bin/config-inputs-user.sh" status zimrc --json-array
```

The retained `status.sh` and `config-user.sh --check zimrc` commands were run
successfully after generation.

## Verification

Full outputs and exit codes are preserved at:

```text
.test-agent/config-contexts/verification/README.md
.test-agent/config-contexts/verification/summary.tsv
.test-agent/config-contexts/verification/logs/
```

The requested sequential README sweep ran once with
`TMPDIR=/home/rektide/tmp-opencode`:

| Group | Result |
|---|---|
| `tests/filter_plugins/*.test.py` | 16/16 passed |
| `tests/lookup_plugins/*.test.py` | 4/4 passed |
| `tests/integration/*.test.py` | 28/31 passed in the sweep |
| `pytest -q tests/links` | 9 passed |
| isolated native `tsgo -p tsconfig.json` | passed |

Integration outcomes:

1. `config_graph.test.py` initially inherited the harness's unrelated `DIR`.
   That direct-leaf test now removes ambient `DIR`; its focused post-fix run
   passes. The shared leaf runtime was intentionally not globally repinned.
2. `opencode_foreground_service.test.py` expects the old argv without CORS;
   current unrelated OpenCode work supplies four `--cors` arguments. No
   OpenCode code/test was changed here.
3. `opencode_status.test.py` timed out after 180 seconds in
   `files/opencode/status-cleanup.sh --no-timer`. No OpenCode cleanup behavior
   was changed here.

Relevant integration passes include config contexts/toolkit, action/status
orchestrator identity, actual Zim host/producer/two-user lifecycle, Mise block
status, canonical donor promotion, LINKS, config graph after isolation, and
existing config-remote behavior.

Native TypeScript verification used the existing isolated scratch package:

```bash
cd .test-agent/config-contexts/typecheck
pnpm exec tsgo -p tsconfig.json
```

No project dependency manifest changed.

## Plain-language final workflow

1. Rerender the updated Zim host playbook into its deployment.
2. Run `bin/install-user.sh` once for complete current-user setup: linked
   baseline inputs, local `zimenv`/`zimrc`, both loader blocks, both caches, and
   canonical registry.
3. Use `config-user.sh --check` and `status-config-context-user.sh` to inspect.
4. Disable/enable current-user modules through `config-inputs-user.sh`.
5. Use explicit drop-in copy/link refresh when wanted; ordinary assembly does
   not refresh.
6. Use whole copy/link as an explicit alternative, and `config-user.sh` to
   return to local assembly.
7. Run `install-zim-donor.sh` only when intentionally changing the shared donor;
   producer ordinary user install changes only that user's context.

Mise remains separate: its Zsh activation arrives through Zim, while its Bash
blocks use `install-bash-user.sh` and `status-mise-bash.sh`.

## Remaining limitations

- No automatic stale-fragment pruning or provenance ledger.
- Canonical admin promotion remains per-fragment/rebuild.
- The dynamic Zim registry manifest is not a static cross-deployment audit
  claim, though actual LINKS apply/status owns its mutation.
- Direct leaf tools may retain their explicit/ambient `DIR` behavior; only
  generated orchestration identity is pinned.
- The two unrelated OpenCode sweep failures remain for their owning work.
- Live deployment and final independent review remain outside this checkpoint.

## Cross-references

- [`build3.solx.md`](/.design/config-user-target/build3.solx.md) is the accepted
  migration checkpoint corrected here.
- [`delivery.ts`](/files/links/delivery.ts) provides physical entry/directory
  comparison and shared atomic delivery.
- [`config-context.ts`](/files/config-context.ts) blocks aliased context output
  commits while preserving preview.
- [`config/toolkit.ts`](/files/config/toolkit.ts) blocks aliased input mutations
  and reports extra-link health.
- [`files/_bin`](/files/_bin) establishes generated orchestrator identity before
  env loading.
- [`orchestrator_identity.test.py`](/tests/integration/orchestrator_identity.test.py)
  and [`config_context_toolkit.test.py`](/tests/integration/config_context_toolkit.test.py)
  are the focused regression proofs.
