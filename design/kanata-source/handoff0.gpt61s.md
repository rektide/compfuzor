---
type: DeploymentCheckpoint
title: Kanata source handoff — preserve config, identity, and uinput access
description: Parent-reviewed build evidence and decisions for the authorized Debian-package replacement, before live cutover.
resource: /design/kanata-source/handoff0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
sources:
  - resource: /design/kanata-source/build0.glm53.md
    title: Source artifact, config validation, package scripts, and prerequisite inventory
  - resource: /design/kanata-source/brief0.gpt61s.md
    title: User authorization and persistent ownership direction
  - resource: /kanata.src.pb
    title: Explicit TCP-capable copy installation
---

# Build checkpoint accepted

The source G ran the existing playbook with the local connector and bounded bypasses, built `--release --locked --features tcp_server`, and copy-installed `/usr/local/bin/kanata` as a real executable. It reports `1.12.1-prerelease-1`, exposes `--port`, and validates both deployed main and BlueTurn configs without opening input devices.

The built revision is upstream `2f84d17`, not a local patch that was discarded. Parent source review confirmed [TCP initialization is conditional on the port argument](https://github.com/jtroo/kanata/blob/2f84d17/src/main.rs#L203-L219) and [gamepad initialization returns immediately without configured gamepad input](https://github.com/jtroo/kanata/blob/2f84d17/src/kanata/mod.rs#L1201-L1215). This is a version change from 1.9, not just relinking an identical build; parse validity and source inspection do not prove physical input feel.

The missing flag is therefore addressed by an installed source artifact. Active service handoff and package removal remain the next slice, not a renewed authorization question.

# Parent decisions

1. **Preserve service identity:** main remains `kanata.service`, with a Compfuzor-owned `/etc` unit taking precedence over Debian's vendor unit. BlueTurn retains its existing identity. Do not install/start the undeployed kinata instance.
2. **Own uinput permissions:** main declares the equivalent `50-kanata-uinput.rules` under `/etc/udev/rules.d`. Do not rely on ydotool or Sunshine continuing to provide matching permissions. Their present redundancy is not Kanata's durable contract.
3. **Own the persistent account:** `_kanata` is a long-lived ordinary system account. UID 990/GID 985 were allocated by `useradd`; that is not `DynamicUser=` lifecycle. Sysusers must preserve existing IDs and establish an account on a fresh machine. Main is the one declarer; helpers consume it with explicit input access.
4. **Preserve live configuration exactly:** main currently excludes only BlueTurn. The authored Kinesis split is not deployed, and this migration must not silently apply it. Do not run filesystem generation against the live main config's symlink target during unit handoff.
5. **Retain sandbox and no listener:** the replacement gains compiled TCP support; no consumer endpoint, broader network access, or command execution feature is introduced here. Endpoint/security changes are deliberate later configuration, not a blocker to building the capability.
6. **Remove, not purge:** remove only package `kanata`; no autoremove. Its `prerm` stops canonical `kanata.service`, and purge would delete `_kanata`. Preserve configuration and identity.

# Safe cutover shape

After reviewing the prepared service declarations and their generated artifacts:

- Save the previously active binary, units/enable links, rule, current config bytes/link targets, and account IDs in scoped rollback material. Do not back up broad private state.
- Install only the prepared account/rule/unit artifacts into durable material. Do not regenerate or replace the active keymaps.
- Verify the source binary and current configs under the intended service identity; inspect generated unit syntax and paths.
- Stop the existing main and BlueTurn instances, install/reload the durable same-name units, and remove the Debian package. Account for the maintainer script's same-name stop rather than assuming it only targets a vendor file.
- Enable/start only the instances that were already deployed. Confirm their actual executable paths and active state; compare config hashes and account IDs to the pre-cutover capture.
- Verify the Kanata-owned udev rule and module-loading dependency survive package removal. Reloading rule definitions is not permission to trigger every input device or reboot the host.
- Record discovery/startup checks separately from manual caps/pedal behavior. Do not inject keys merely to claim end-to-end verification.

The input units will recreate their virtual devices during this authorized cutover. A failed start requires recovery to the preserved previously working binary/unit/config state, not experimentation with the keyboard split or broad sandbox removal.

# Configuration boundary retained

Dial policy remains producer/daemon-owned in media-keys and/or Surface Dial. Umbriel receives generated native bindings if that execution path is chosen. This binary/service migration introduces no new dial keys, step values, mode bit, or compositor state store.

# History housekeeping

A concurrent change-ID collision involved the source G's checkpoint-only commit and unrelated kernel work. Parent inspected the checkpoint commit and assigned **only that commit** a new change ID with `jj metaedit --update-change-id`; no file content was discarded, no duplicate/abandon was needed, and unrelated kernel work was not removed.
