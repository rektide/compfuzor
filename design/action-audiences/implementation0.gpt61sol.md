---
type: ImplementationCheckpoint
title: Audience action families — verified composition seam
description: Implemented opt-in mjs action families and shared execution, with domain binding and deployment placement awaiting review.
resource: /design/action-audiences/implementation0.gpt61sol.md
status: draft
generated: { by: model:gpt61sol, at: 2026-10-06 }
verified: { by: model:gpt61sol, method: isolated-tests-and-source-review }
sources:
  - resource: /design/action-audiences/implementation-plan0.gpt61sol.md
    title: Proposed admission checkpoint, subsequently refined by parent authorization
  - resource: /library/filter_plugins/action_audiences.py
    title: Implemented controller seam
  - resource: /files/actions/runtime.ts
    title: Implemented selection and execution contracts
  - resource: /tests/integration/action_audiences.test.py
    title: Generated artifact, scoped execution, stale-entry and signal evidence
---

# Outcome and review boundary

The first authorized slice is implemented: opt-in user-first action plans,
one real qualified `.mjs` per action/subsystem, symlink aliases, shared runtime
execution, catalog observation and isolated tests. **Paused before domain
integration.** No live receiver/service change, migration, placement switch,
desktop reload or push occurred. Unrelated working-copy edits were excluded.

Source checkpoints:

- `e88950ed` — first compiler/shared-adapter seam and unit tests.
- `87923ed6` — corrected authored-body identity, current-spec guards, execution
  tests and Node-compatible built runtime.
- `455fdc6b` — isolated full render of the real SteamOS mixed-scope declaration;
  provisioning and user-adoption bodies retained without executing either.

These preserve the predecessor rather than rewriting/squashing it. The first
checkpoint's private-path body proposal is superseded by the second checkpoint's
original-path bridge, for the concrete `$0` reason below.

# Exact changed paths

| Area | Paths |
|---|---|
| Compiler | [`action_audiences.py`](/library/filter_plugins/action_audiences.py) |
| Shared implementation | [`runtime.ts`](/files/actions/runtime.ts), [`entry.ts`](/files/actions/entry.ts), [`compfuzor-runtime.ts`](/files/runtime/compfuzor-runtime.ts) |
| Ansible materialization | [`gen_bins.tasks`](/tasks/compfuzor/gen_bins.tasks), [`bins_link.tasks`](/tasks/compfuzor/bins_link.tasks), [`_bin`](/files/_bin) |
| Catalog | [`runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py) |
| Distribution/checking | [`tsconfig.json`](/tsconfig.json), [`compfuzor-runtime.mjs`](/runtime/compfuzor-runtime.mjs) |
| Tests | [`action_audiences.test.py`](/tests/filter_plugins/action_audiences.test.py), [`selection.test.ts`](/tests/action-audiences/selection.test.ts), [`integration test`](/tests/integration/action_audiences.test.py) |
| Maintained contract/navigation | [`doc/actions/README.md`](/doc/actions/README.md), [`doc/config/README.md`](/doc/config/README.md), [`inquiry index`](/design/action-audiences/index.md), this checkpoint |

`BIN_ACTIONS`, `USERMODE`, package metadata, CONFIG/keybinding operations and
deployment hierarchy variables were not changed.

# Generated family and data

For two audience-specific assembly leaves:

```text
assemble-user.mjs                  # real
assemble.mjs -> assemble-user.mjs
assemble-system.mjs -> assemble-user.mjs
```

The real file is under 220 bytes in the integration fixture:

```js
#!/usr/bin/env node
import { actionEntry } from "./compfuzor-runtime.mjs";
actionEntry(process.argv.slice(2), process.argv[1], import.meta.url);
```

The relevant `etc/compfuzor-actions/spec.json` family is:

```json
{
  "version": 1,
  "actions": {
    "assemble": {
      "name": "assemble",
      "action": "assemble",
      "entry": "assemble-user.mjs",
      "aliases": ["assemble.mjs", "assemble-system.mjs"],
      "default": "user",
      "plans": {
        "user": [{"kind": "exec", "path": "bin/assemble-receiver-user.sh"}],
        "system": [{"kind": "exec", "path": "bin/assemble-receiver.sh"}]
      }
    }
  }
}
```

Subsystem steps use `{kind: "action", action: "install-systemd"}` and execute
that subsystem's lexical qualified alias. An authored shell body becomes one
exec step with `children` metadata for graph preflight; the shell bridge owns
executing those children, so they are **not executed twice**.

# Decisions and evidence refinements

- **No implicit fallback.** Missing default-audience work means no bare alias,
  even when the other audience has work. Explicitly contradictory declared
  default/availability is rejected; a missing contributed default plan is not
  a fabricated success or a fallback. Global availability can only be narrowed
  per action. Empty placeholder roots do not create plans.
- **Hard qualified selection.** Unknown/stale spellings fail against the current
  spec. No generic context flag rewriting was introduced. Existing domain
  precedence remains unchanged, with its admission gap identified below.
- **Body identity matters.** Moving authored roots beneath `internal/` would
  change `dirname($0)`. They therefore retain their original shell filename as
  an internal body bridge with a current-spec guard. Existing exported state,
  original `run_all`, bypass and `late` ordering survive. Body-local bypass skips
  only authored work; children continue exactly as before.
- **Current spec owns availability.** Omitted actions publish a fresh spec,
  including `{actions: {}}`; stale public entries and old body bridges cannot
  execute through their old claims. No automatic pruning is introduced.
- **Catalog is observation, not double-scope execution.** New-mode authority is
  `action-audiences` with `catalogOnly: true`. Combining it with the existing
  unscoped native-flow executor is rejected, not silently weakened.
- **Node compatibility exercised.** Real/alias entries, their internal body
  guards and the shared bundle execute under installed Node **20.19.0**, not
  merely newer TypeScript stripping. The existing Vite target remains unchanged.

# Verification

Passing checks:

- Controller compiler tests: defaults, per-action restrictions, omission,
  collisions, scopes, phase order, original body metadata and catalog contracts.
- `pnpm exec vp test run tests/action-audiences tests/config-keybindings --maxWorkers=2`:
  **6 files, 30 tests passed** (all Vitest files under `tests/`).
- Isolated Ansible/render/execution test under Node **26.6.0** and **20.19.0**:
  both defaults; representation flips; system-only/no-bare policy; generic
  assembly; original `$0`; forwarded spaces; exported body state; body bypass;
  packages/user-manager/system-manager/records order; lexical leaf and external
  aliases; unknown/stale/omitted entries; current-spec body rejection; cycles;
  preflight containment before any effect; exact exit 7; forwarded and child
  SIGTERM with no later work.
- Isolated full-framework SteamOS playbook render: explicit system provisioning
  and user adoption retain their different bodies and package/keybinding children;
  no generated installation, native validation or service operation was executed.
- `pnpm check:type`; targeted Vite lint/format; existing bin-composer and runtime
  catalog controller tests; legacy body-disarm and catalog-flow integration tests.

An unrestricted `vp test run` was attempted but did not complete within its
120-second execution limit; it also discovers the archive's separate `node:test`
files as zero-test Vitest suites. The scoped, two-worker Vitest run above completed
successfully. No claim is made that all unrelated Python/Ansible/archive suites ran.

The normal build initially incorporated pre-existing uncommitted
`files/config/registration.ts` edits into the omnibus artifact. To avoid committing
someone else's pending work indirectly, the committed bundle was built in
gitignored `.test-agent/action-audiences/` using our current source and the
committed registration source at `2ef46a05`. Only scratch-relative dependency
**comment** labels were canonicalized. The user's source remained untouched;
the final installed-artifact integration tests ran against this isolated bundle.
Ordinary future builds will naturally include registration once its separate work
is committed. No archive bundle or unrelated source was included in our commits.

# Review concerns and proposed next slice

This seam makes scoped executable contributions and different user/system plans
possible. It does **not** yet make old context-selecting leaves safe under a new
audience alias: e.g. current `config-install.sh` is an unscoped leaf whose internal
default may be user. Adding aliases alone would misclassify that effect. Likewise,
domain overrides can still change contexts; a general flag scrubber is not the fix.
Do not broadly opt existing deployments into this mode until their domain mapping
is admitted. No real playbook was opted in during this slice.

Recommended domain interface for the next review:

1. Domain compilers contribute an audience-bound **complete operation**, not a
   committing operation hidden inside a candidate processor. A typed action step
   can carry a CONFIG action/context or keybinding target/profile/context, then
   dispatch the existing import-safe operation through shared services.
2. CONFIG can infer one noncanonical context per scope; ambiguous same-scope
   contexts need an explicit domain mapping such as
   `CONFIG_ACTION_CONTEXTS: {user: desktop, system: host}`. Canonical donor
   assembly must not become a system installation plan. Retain install ownership.
3. Each adapter validates the effective selected context/profile scope against the
   chosen audience and owns its domain flags. Preserve low-level CLI precedence;
   do not reinterpret every domain's flags in the general executor.
4. Keybinding hosts attach `assemble` with native placement mode `assemble`;
   complete install keeps its seed/registration/membership operation. Producer
   install is not replaced by host-only assembly. CONFIG and keybindings can be
   sequential complete transactions; no claim of one joint candidate set.
5. Zim's complete install keeps loader/cache/registry effects, not merely CONFIG
   assembly. Domain-specific named contexts remain meaningful.

Potential typed steps for discussion, **not an implemented schema**:

```text
config operation:      action=assemble, context=desktop, spec=deployment CONFIG
keybinding operation:  action=assemble-host, target=niri, profile=declared selector,
                       context=desktop
```

Review whether these should be in-process action steps or attributed executable
operations before implementation. Both must keep complete-operation boundaries
and selected audience explicit. Placement remains separately deferred: evaluate
existing DIR/ETC/artifact/source primitives before authorizing `MATERIAL_ROOT` or
another placement declaration. No home-local layout code was added here.

# Cross-references

- [Maintained contract](/doc/actions/README.md): current operator/schema semantics
  and the domain-adoption warning, not just proposed research.
- [Intent](/design/action-audiences/intent0.gpt61sol.md): user-first behavior and
  home-local material remain distinct obligations.
- [CONFIG evidence](/design/action-audiences/config-stages0.gpt61sol.md): why
  assembly/install/publication remain complete, different operations.
- [Alias evidence](/design/action-audiences/action-variants0.gpt61sol.md): lexical
  invocation/physical rooting precedent and why source `.mts` was not required.
- [SteamOS declaration](/steamos-niri.opt.pb): representative distinct authored
  provisioning/adoption bodies preserved by this seam, but not opted in yet.
