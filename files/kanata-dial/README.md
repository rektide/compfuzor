# Kanata dial material

[`kanata-dial.etc.pb`](/kanata-dial.etc.pb) packages these dependency-free
TypeScript sources alongside the scoped dial map and example keyboard signal.
Node with native TypeScript stripping is required; there is no build step.

- `protocol.ts`: bounded newline JSON framing and installed-protocol spelling.
- `relay.ts`: keyboard layer snapshots/updates → target virtual-key hold,
  independent reconnect, periodic liveness query, reset-before-apply and stop reset.
- `cli.ts`: explicit loopback endpoints from environment; `--reset` needs only target.
- `toggle.ts`: user enhancement ON/OFF over existing keybinding membership commands,
  explicitly authorized systemctl operations and an explicit compositor apply hook.
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

System installation explicitly copies runtime assets into `/etc/opt/kanata-dial-main`
and unit files into the system manager. It does not enable/start them or install
user membership. The generated user `apply` action accepts `on|off`, explicit
receiver profiles and `--apply-command /absolute/operator-hook`; there is no
default compositor reload. OFF disables/stops the relay, confirms namespace-local
fallback, then disables membership. Dial and anchor stay available in legacy mode.

System services use `/usr/bin/node`, never a home/Mise executable. Native TS's
WebAssembly needs a narrow relay/reset executable-memory exception; input units
retain memory-execution denial. The namespace anchor has no input permissions.

See [implementation checkpoint](/design/kanata-dial/implementation2.gpt61sm.md)
for integration gates and known passthrough/Zoom limits.
