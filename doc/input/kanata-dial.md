---
type: ImplementationGuide
title: Optional TCP-controlled Kanata dial precision
description: Separate media contribution, keyboard-to-dial signal, explicit installation/toggle audiences, and deployment gates.
resource: /doc/input/kanata-dial.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
stale_after: 2026-11-07
sources:
  - resource: /kanata-dial.etc.pb
    title: Producer and private service artifact declarations
  - resource: /kanata.srv.pb
    title: Optional keyboard publisher
  - resource: /design/kanata-dial/review0.gpt61s.md
    title: Parent offline integration review
---

# What it does

[`kanata-dial.etc.pb`](/kanata-dial.etc.pb) packages a separately selectable producer group, `kanata-dial`, and private system service artifacts. It leaves Surface Dial and base media actions unchanged.

```text
keyboard Shift → main's transparent dial-precision layer
              → private TCP relay
              → dial's precision-hold virtual key
              → F23/F24 → optional 0.003 volume actions

relay OFF → dial base → legacy Shift+Volume → existing 0.01 media actions
```

The raw dial virtual keyboard is captured separately. Main must exclude it and the normalized output; the main integration flag adds those exclusions. TCP control uses two private loopback endpoints, with a stable network namespace anchor rather than a host-exposed listener.

# Interfaces and boundaries

- `install-user.mjs`: producer registration through the existing receiver-selection mechanism, no service start.
- `install-system.mjs`: explicit system runtime/unit copying and daemon reload, no automatic enable/start.
- `apply-user.mjs on|off`: ordered enhancement control with explicit receiver profiles and an application/readiness hook.
- `KANATA_DIAL_PRECISION_STEP`: defaults to `0.003`, configurable at render time.
- Main's `KANATA_DIAL_ENABLED`: defaults off. Main still owns its keyboard config, account, and service. Select `KANATA_DEV_NAMES_EXCLUDE` explicitly to preserve the intended topology; the current authored/live Kinesis distinction remains real.

The implementation is **not deployed**. Rendering packages inert material. Do not substitute a normal main render for a reviewed live handoff or blindly preserve a stale config while expecting the new publisher to be active.

# After deployment approval

Install the separate system artifacts and deliberately install/restart the main publisher with the correct exclusion list. Then use the generated user apply entry with the intended receivers:

```sh
material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/kanata-dial-main"
"$material/bin/apply-user.mjs" on \
  --umbriel-profile /absolute/path/to/keybinding-umbriel.json \
  --apply-command /absolute/path/to/application-readiness-hook
```

The hook receives on/off and the selected target/profile/context arguments. On ON, it must explicitly apply compositor configuration and confirm the plain and Shift F23/F24 directions are active. Group enablement alone preserves user-disabled slots and edited native placements; command success alone is not a binding-readiness proof. No default automatic reload or invented inventory API is supplied.

For OFF, use the same entry with `off`. It disables/stops the relay, requires observed dial fallback through a namespace-local reset, then disables memberships and invokes the hook. Dial and anchor remain available for legacy volume. If reset fails, it stops dial as fail-safe and retains F bindings; repair before retrying. Do not directly disable membership while a relay can still emit precision keys.

This requires separately approved noninteractive authority for the selected systemctl operations. Membership, service state, and compositor application are not one transaction. Only one toggle/controller may own the precision key. Persistent boot enablement is not inferred from membership.

# Verification

Offline tests passed for mock TCP lifecycle/reset, native Node execution, toggle ordering/failure handling, producer compilation, isolated rendering/copying, parser checks, static unit verification, and preservation of main's default behavior. No live input or service activation was used to claim hardware behavior.

See [implementation evidence](/design/kanata-dial/implementation2.gpt61sm.md), [parent review](/design/kanata-dial/review0.gpt61s.md), [relay code](/files/kanata-dial/relay.ts), and [toggle code](/files/kanata-dial/toggle.ts). Device-ID/history improvement is [parked separately](/design/kanata-devices/index.md).
