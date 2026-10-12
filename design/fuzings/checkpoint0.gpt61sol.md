---
type: ImplementationCheckpoint
title: Native-root resolver checkpoint before concrete proxy adoption
description: Narrow explicit native input delivery preserved separately from the multi-CONFIG and env.d baseline; broader integration deferred.
resource: /design/fuzings/checkpoint0.gpt61sol.md
status: experimental
generated: {by: 'model:openai/gpt-6.1-sol#xhigh', at: 2026-10-12}
sources:
  - resource: opencode://ses_ed21877fbffeK90YzBIZKC1jHb
    title: shiny-sailor — preserve the resolver started before scope narrowed, then verify bounded direct behavior
  - resource: /design/fuzings/contract1.gpt6a.md
    title: Proposed root enrollment and copy/link seam
  - resource: /design/fuzings/implementation0.gpt6a.md
    title: Predecessor landing sequence
  - resource: /files/config/fuzings.ts
    title: Direct native-root resolution/delivery implementation
  - resource: /tests/integration/config_fuzing_checkpoint.test.py
    title: Isolated copy/link, recognition, explicit refresh, and disabled/idempotent proof
---

# Boundary

The user narrowed this assignment to multiple complete CONFIGs, separate normal
ZIM, and env.d. A **fresh Sol xhigh** should adopt that baseline for opencode-bus-proxy
before wider fuze design/integration is reconsidered. This preserves the small resolver
already started, without deleting or silently promoting it. The maintained
[baseline interface](/doc/config/definitions.md) links back here. No proxy/OpenCode
adoption or live activation occurred.

# Implemented checkpoint

A glob input can carry consumer-owned native recognition:

```yaml
inputs:
  - glob: pieces/*.conf
    name: fragments
    fuzings:
      roots: fuze.d
      paths: [native/*.conf]
```

Roots are explicitly enrolled symlinks. Directories are concrete; filenames can have
globs. Unrecognized files are inert. Member plus relative source path qualify identity.
Members sort by name, then authored rules and native filenames. No per-member JSON
descriptor is introduced.

```sh
bin/config-inputs.sh --definition native --context canonical \
  fuze put main/fragments producer /owned/producer/contribution-root
bin/config-sync-inputs.sh --definition native --context canonical --strategy copy
bin/config-inputs.sh --definition native --context canonical fuzings main/fragments
bin/config-assemble.sh --definition native --context canonical
```

Existing copy/link primitives deliver derived
`<input-directory>/.fuzings/<member>/<relative-file>` entries. Links address producer
material, not the toggleable enrollment alias. Assembly selects currently enabled,
recognized membership and consumes installed representations; check does not refresh
copies. Newly recognized material requires delivery. Missing active source/installed
inputs fail before output publication. Raw worker and CLI use the same resolver.

`fuze enable|disable INPUT MEMBER` toggles enrollment's .disabled state. Exact repeated
put preserves that state; foreign enrollment/link slots fail. Disable excludes retained
derived material without pruning. Rendering/assembly does not install/clean membership.

config_fuzing_checkpoint.test.py verifies direct CLI/worker concat behavior: recognition,
copy/link, copy refresh, new-file prerequisite, idempotence, disable/re-enable exclusion,
and retained material. It is not ENV/OpenCode semantic admission or ZIM cache activation.

# Deferred

- ENV_CONFIG does not automatically adopt these enrollment rules.
- Remote fanout scans selected deployment CONFIGs, not enrolled foreign consumers.
- General audience-action input admission and full CONFIG drift/status do not yet
  expose root membership consistently; use its direct fuzings inventory.
- Per-file control UX, copied-slot ownership proofs, source/winner provenance,
  removal/rebinding/required-input policy, and multi-member atomicity need assessment.
  Copy/link mutations are not a global transaction.
- No prune, scheduler, universal type dispatcher, or new merger was introduced.

Neither the old files/fuzings pilot nor this checkpoint mandates a schema. Preserve
their evidence, adopt the baseline for the concrete proxy first, and then choose the
smallest useful native relationships and operation surface.
