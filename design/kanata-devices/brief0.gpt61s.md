---
type: InquiryBrief
title: Improve Kanata Linux device-aware keyboard processing
description: Investigate preserving keyboard device provenance, device-conditioned mappings, and independent held-key state rather than requiring separate daemon instances.
resource: /design/kanata-devices/brief0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-07 }
sources:
  - resource: /design/surface-dial-layers/dial-remap0.gpt61s.md
    title: Verified Linux input-merging limit and the scoped-instance workaround
  - resource: /design/surface-dial-input/kanata-assessment0.gpt61s.md
    title: Earlier merging and same-key release analysis
  - resource: /design/kanata-source/cutover0.glm53.md
    title: Active source-built Kanata version and deployment boundary
---

# User request

The user considers the lack of device-conditioned Linux keyboard processing a substantial limitation and explicitly asks a G to investigate whether Kanata can be hacked to do better. This is source/architecture inquiry, not authorization to patch source or redeploy input services.

# Concrete motivating case

Surface Dial emits synthetic Shift+Volume through its own uinput keyboard. We want to consume only that device's Shift and normalize its Volume events to a distinct vocabulary, while preserving physical keyboard Shift for media-keys action selection. A separate Kanata instance can scope the transformation, but one Linux instance currently discards source identity before shared rule processing.

Broader motivation: multiple keyboards, pedals, and controller-like virtual devices need distinct semantics without proliferating services, while retaining useful shared layers/chords where explicitly wanted.

# Investigation questions

1. Where exactly is device provenance discarded, and which Linux/backend/shared event interfaces would need to carry it?
2. What can be reused from existing `definputdevices`, macOS device history, controller matching, parser, queues, and state-engine machinery?
3. Distinguish three capabilities: device-conditioned actions, independent held-key/layer state, and shared logical output aggregation. Which does a minimal hack deliver or leave broken?
4. How should simultaneous identical keys, modifier release, hardware repeats, queued/custom actions, hotplug, removal, reconnect, reload, unprocessed passthrough, and TCP/fake input behave?
5. Compare a small device-history port, device-conditioned normalization before merger, and deeper per-device state/mapping ownership. Identify coherent implementation seams without prematurely choosing one.
6. What existing pure tests/simulators can reproduce the two-device Shift problem and the desired dial normalization without grabbing input?

# Boundaries and evidence

Inspect the local archive first: `~/archive/jtroo/kanata`, deployed source revision `2f84d17`, package `1.12.1-prerelease-1`. Preserve any subsequent user work and source revision differences; no checkout/reset/fetch/install/restart or live config mutation. Existing docs establish that Linux `KbdIn` tracks devices for polling but appends untagged events, and keyboard `device-history` is documented as macOS-only. Verify rather than assuming those interfaces cannot evolve.

The parent retains architecture responsibility. G should return a source-backed checkpoint explaining what becomes possible, which invariants remain unresolved, and the smallest justified next slice. A parseable schema alone is not proof of device-aware processing or independent modifier ownership.
