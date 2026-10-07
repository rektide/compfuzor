---
type: ImplementationCheckpoint
title: Observed fallback reset and optional offline dial integration
description: Parent-approved revision of native TypeScript execution, final precision amount, reset safety and forthcoming service/toggle artifacts.
resource: /design/kanata-dial/implementation1.gpt61sm.md
status: draft
generated: { by: model:gpt-6.1-sol-medium, at: 2026-10-07 }
sources:
  - resource: /design/kanata-dial/implementation0.gpt61sm.md
    title: Saved predecessor and initial implementation
  - resource: https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/mod.rs#L3067-L3088
    title: Fake-key commands enqueue layout events rather than synchronously completing layer processing
---

# Review delta

The parent reviewed the first slice and authorized continued **offline**
integration. The human selected precision **0.003** and enhancement-only OFF:
retain the dial remapper's legacy Shift+Volume fallback. F23/F24 are allocated
to precision directions in this contribution. Device-identity research is parked.
No live service, listener, input, compositor or privileged operations are authorized.

## Corrected protocol/runtime boundary

- Native TypeScript execution does not support constructor parameter properties.
  Runtime classes now use explicit members/assignments; domain tsconfigs set
  `erasableSyntaxOnly`. The actual `/usr/bin/node` native-TS reset CLI is tested
  against a mock server rather than trusting Vitest's transform.
- Fake-key Release queues a layout event. A following query can still report
  `precision`. Startup reset and stop reset now poll boundedly until an actual
  `CurrentLayerName` response equals configured fallback `base`; malformed/missing
  or perpetually wrong layer fails rather than admitting OFF. Initial target
  connection cannot apply held source state until fallback has been observed.
- The reset helper checks virtual-key existence; source and target must have
  distinct ports. Named key/layer identifiers are validated. No fake action ACK
  or completed OS-output ACK is invented.
- Mock tests delay effective-layer processing, return stale precision first, and
  reject a target that remains stuck. The first revision passed 13 Vitest tests
  and its native-TS typecheck.

Parent independently verified `/usr/bin/node` v26.10.0 and systemd 262-1.
`--jitless` prevents the WebAssembly needed by Node's TypeScript stripping;
`--no-expose-wasm` is unsupported. Do not use those flags. The narrow relay-only
runtime exception is `MemoryDenyWriteExecute=false`; input units retain true.
Relay still needs DynamicUser, no input group/device binding, empty capabilities,
NoNewPrivileges and shared private loopback networking. System runtime must use
the public `/usr/bin/node`, not the controller's home/Mise executable.

# Integration gate

The next coherent artifact stage will add stable namespace anchor, explicitly
copied system assets, scoped system install, user enhancement toggle and optional
main-owner flag. These are not yet deployed. Tests and exact generated interfaces
will be recorded before returning the next architectural checkpoint.

# Cross-references

- [Initial checkpoint](/design/kanata-dial/implementation0.gpt61sm.md) preserves
  the original dispatch-barrier-only design and explains why it needed correction.
- [Runtime README](/files/kanata-dial/README.md) documents the current reset and
  native TypeScript contract.
- [Mock lifecycle tests](/tests/kanata-dial/relay.test.ts) cover stale-layer polling,
  hung reset, native Node CLI, reconnect and duplicate suppression.
