---
type: ImplementationReview
title: Kanata dial contribution — offline integration review
description: Parent code review of the completed contribution, native runtime and reset corrections, and deployment gates left explicit.
resource: /design/kanata-dial/review0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
sources:
  - resource: /design/kanata-dial/implementation2.gpt61sm.md
    title: Sol M integration checkpoint and reported checks
  - resource: /kanata-dial.etc.pb
    title: Optional producer, service declarations, runtime-copy boundary
  - resource: /kanata.srv.pb
    title: Optional keyboard publisher and capture handoff fence
  - resource: /files/kanata-dial/relay.ts
    title: Snapshot forwarding and observed fallback reset
  - resource: /files/kanata-dial/toggle.ts
    title: Explicit system/membership/application sequencing
---

# Outcome

The requested implementation is complete through the offline gate. Sol M saved runtime/reset corrections as `223a7c03` and integration as `630977a9`. Parent read the actual playbook, main-owner integration, relay/protocol/CLI, toggle and tests, rather than approving solely from the checkpoint summary. No live activation is authorized or claimed.

The selected increment is **0.003**. Base media `.03/.01` stays user-owned and unchanged; Surface Dial source is unchanged. The separate `kanata-dial` group contributes F23/F24 precision bindings. OFF means enhancement-only off: stop/reset the relay before disabling that group, leaving the scoped remapper in legacy Shift+Volume fallback.

# Reviewed architectural fit

- **The TCP bit has a real effect:** baseline emits legacy media chords, while the held virtual precision key selects F23/F24. Physical-Shift F variants are bound too, but physical Shift alone does not substitute for the TCP layer selection.
- **Keyboard signaling stays with its owner:** main has a default-OFF integration flag, transparent Shift-held layer, explicit exclusion-list override, and private listener configuration. It neither replaces the selected live topology automatically nor adopts kinata.
- **Device ownership is fenced:** dial startup requires main's enabled config marker and current-invocation runtime directory. This guards a common stale-process/artifact handoff, not arbitrary operator mistakes or a general input-security proof.
- **System artifacts do not point into HOME:** explicit system installation copies runtime assets and unit files to durable/public system locations. User producer membership remains a distinct action audience and transaction.
- **Control traffic stays private:** a stable non-input namespace anchor is shared by the input participants and relay/reset. TCP allowances are loopback-only; the Node processes have no input-device bindings and the input daemons retain executable-memory denial.
- **Runtime corrections are present:** parameter properties were removed from native `.ts` runtime files. Reset waits for the known fallback layer rather than accepting any query reply. Delayed-processing and stuck-state mocks cover the previously inadequate dispatch-barrier assumption.

# Evidence and limits

Sol M reports 21 passing domain tests, native Node mock CLI, domain typecheck/lint, real isolated renders and scratch-only copying, installed Kanata parser checks, static systemd validation, and the existing source-service regression/live-fence checks. Parent did not rerun those routine checks. Independent parent checks previously established the Node TS/JITless incompatibility and inspected upstream fake-key event queuing and systemd namespace semantics.

These are not live namespace, hardware, compositor, or actual service-start tests. Input timing, dual-Shift/caps behavior, reconnect counts, wheel/Zoom/mute behavior and whole-live-graph F-key collisions remain acceptance checks before deployment. The layer-name adapter represents the selected main instance's effective layer, not all physical modifiers from every instance or an arbitrary future stack.

# Deployment remains deliberate

The required readiness hook is **not** implemented as a generic compositor-binding inventory. An operator supplies explicit receiver profiles and an application/readiness command whose success means both directions, plain and Shift, are active. This is necessary because group enablement preserves disabled individual slots and edited placements. An arbitrary successful hook such as `true` would not satisfy that contract.

The toggle is explicit orchestration, not a cross-audience CONFIG transaction or a privilege broker. It uses approved noninteractive systemctl authority and one-controller/one-toggle ownership. ON does not infer persistent boot enablement. OFF explicitly prevents relay restart, observes fallback, then disables memberships. Reset failure stops the dial and retains bindings; successful fallback retains ordinary volume. Partial receiver state can remain after failure and is reported rather than falsely rolled back.

Before activation, install the system artifacts, deliberately enable/install/restart main with the intended exclusion list, validate/apply the selected consumers, and perform hardware acceptance. Do not turn on raw capture against a still-running main that owns the same node.

# Next work

Device-ID/history inquiry remains parked for the requested later session. This contribution intentionally uses existing scoped instances. No upstream hack, Surface Dial actuation engine, compositor-owned dial policy, or live TCP deployment was slipped into the implementation.
