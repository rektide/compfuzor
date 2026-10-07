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

`ActOnFakeKey` has no success ACK. The reset helper waits for a subsequent query
reply on the same stream, establishing dispatch ordering, not completed input
processing. A failed reset must prevent binding disable unless the dial instance
is stopped. SIGKILL cannot run cleanup: proposed systemd `ExecStopPost=… --reset`
and reset-on-reconnect are required crash recovery, not an automatic TCP lease.
Only one controller may own `precision-hold`.

See [implementation checkpoint](/design/kanata-dial/implementation0.gpt61sm.md)
for integration gates and known passthrough/Zoom limits.
