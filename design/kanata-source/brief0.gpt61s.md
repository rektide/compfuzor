---
type: MigrationIntent
title: Replace Debian Kanata with the source-built capability lane
description: Authorized source build and package replacement while preserving input ownership, service identity, accounts, and configuration.
resource: /design/kanata-source/brief0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
sources:
  - resource: /kanata.src.pb
    title: Existing source build playbook
  - resource: /kanata.srv.pb
    title: Main service currently dependent on Debian's package and unit
  - resource: /kanata-blueturn.srv.pb
    title: Pedal service consuming the same packaged binary/account
  - resource: /kinata.srv.pb
    title: Declared keyboard-specific service consuming the same package
  - resource: /design/surface-dial-layers/routing0.gpt61s.md
    title: Prior installed-build and transport limitations
---

# User steering and scope

The user explicitly authorizes running `kanata.src.pb` and uninstalling Debian Kanata if the missing TCP facility is a Debian-build limitation. This is **a replaceable deployment choice, not a fundamental Kanata blocker**. They also clarify that authoritative dial configuration belongs in media-keys and/or Surface Dial, not Umbriel.

Read-only checks found installed package `kanata 1.9.0+ds-1`, with no TCP port flag in the binary's help. The archived source manifest includes `tcp_server` in its default feature set. A background G owns source-build execution and package/migration evidence. Passwordless sudo is available.

The authorization is scoped: build/install the replacement, preserve active input behavior, remove the Kanata Debian package deliberately, and make persistent playbooks reflect the source lane. It does not authorize apt autoremove/purge, unrelated upgrades, new dial behavior, arbitrary external listeners, or adoption of an undeployed keyboard split.

# Architectural checkpoints

1. **Build capability:** run the existing playbook with the local Ansible connector, preserving archived user source and avoiding unrelated source refreshes. Produce a service-readable source binary that advertises TCP support and validates existing active configs without grabbing devices.
2. **Ownership handoff:** identify package-owned unit/config/account files and maintainer-script behavior. Prepare a durable main service and shared account independent of the package; update every declared consumer that would otherwise reinstall Debian or reference `/usr/bin/kanata`.
3. **Active cutover:** only after reviewing the built artifact and handoff, switch existing service instances and remove the single Debian package without purging configuration. Retain enough material to recover the previously working deployment. Verify active binary/config selection and absence of the package.

The parent retains architectural responsibility; G may implement coherent approved slices, but package removal and live service cutover wait for the build/ownership checkpoint. This is an internal safety gate, not a request to re-authorize the user's already-authorized migration.

# Persistent ownership direction

- [`kanata.src.pb`](/kanata.src.pb) owns building and installing the capability-enabled binary. Prefer the existing `RUST_COPY: True` support for a real executable under `/usr/local/bin`; a symlink through the archive/home can be inaccessible to `_kanata` under `ProtectHome`.
- [`kanata.srv.pb`](/kanata.srv.pb) owns main's configuration and service independently of Debian. Preserve the canonical `kanata.service` identity deliberately rather than inadvertently creating a differently named service with a competing alias.
- The existing [sysusers generator](/tasks/compfuzor/gen_sysusers.tasks) can give one playbook ownership of `_kanata`; other instances consume that account. Preserve its existing UID/GID and explicit input access where possible.
- [`kanata-blueturn.srv.pb`](/kanata-blueturn.srv.pb) and [`kinata.srv.pb`](/kinata.srv.pb) must not retain a Debian package dependency or a removed binary path. Do not activate kinata merely because its playbook exists.
- Do not overwrite the active main config with the playbook's Kinesis exclusion while the corresponding dedicated instance remains undeployed. Binary migration and input ownership changes are separate decisions.
- Binary TCP capability and **starting a listener** are separate. The current network sandbox is configurable; retain unrelated protections and choose endpoint/namespace/access deliberately when a protocol consumer is introduced.

# Dial configuration boundary

Authoritative action/tier/step policy belongs in [`media-keys.etc.pb`](/media-keys.etc.pb) and/or [`surface-dial.src.pb`](/surface-dial.src.pb), or the daemon's own configuration if it executes actions. Umbriel may contain generated native binding artifacts as an execution target; it should not become the source of dial policy or a generic dial state store.

The [precision-layer checkpoint](/design/surface-dial-layers/syn0.gpt61s.md) remains useful, but its Debian transport restrictions are now **migration prerequisites being addressed**, not reasons to dismiss the sideways-state path. Publisher provenance, snapshot/liveness behavior, and source/action ownership remain genuine design questions even after replacing the binary.

# Evidence and verification boundaries

The archived checkout is currently a `1.12.1-prerelease-1` source tree, not the installed package's version. Its local work and exact revision must be reported before cutover; config syntax validation is necessary but does not prove physical tap-hold or pedal behavior. Avoid disguising a source-version change as a feature-flag-only change.

Native project guidance: [systemd generation](/skill/systemd.md), [Rust installer behavior](/vars/common.yaml), [sysusers rendering](/library/filter_plugins/sysusers.py). No generic generator redesign or new network/protocol implementation is part of this migration unless a concrete verified need is approved.
