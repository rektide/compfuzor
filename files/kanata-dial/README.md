# Kanata dial material

[`kanata-dial.etc.pb`](/kanata-dial.etc.pb) packages these dependency-free
TypeScript sources alongside the scoped dial map and example keyboard signal.
Node with native TypeScript stripping is required; there is no build step.

- `protocol.ts`: bounded newline JSON framing and installed-protocol spelling.
- `relay.ts`: keyboard layer snapshots/updates → target virtual-key hold,
  independent reconnect, periodic liveness query, reset-before-apply and stop reset.
- `cli.ts`: explicit loopback endpoints from environment; `--reset` needs only target.
- `dial.kbd`: raw synthetic Shift consumed; legacy Shift+Volume fallback;
  held precision emits F23/F24.
- `keyboard-signal.example.kbd`: parser-checkable example, **not** the main config.

`ActOnFakeKey` has no success ACK. Reset sends Release and polls current layer
until the configured fallback (`base`) is observed, within a bounded deadline.
This proves effective-layer fallback, not completed OS output. A failed reset
must prevent binding disable; stopping the dial instance is the fail-safe and
bindings remain enabled until a later successful OFF. SIGKILL cannot run cleanup:
systemd `ExecStopPost=… --reset`
and reset-on-reconnect are required crash recovery, not an automatic TCP lease.
Only one controller may own `precision-hold`.

The final selected precision amount is `0.003`; media `.03/.01` remains unchanged.
Native Node execution is tested with `/usr/bin/node`. Runtime TypeScript uses
erasable syntax only (no constructor parameter properties).

See [implementation checkpoint](/design/kanata-dial/implementation1.gpt61sm.md)
for integration gates and known passthrough/Zoom limits.
