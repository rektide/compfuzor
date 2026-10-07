---
type: CutoverReport
title: kanata live cutover — source binary active, Debian package removed
description: Executed the authorized handoff; both instances run /usr/local/bin/kanata 1.12.1-prerelease-1 with configs, account, and link topology byte-identical to preflight.
resource: /design/kanata-source/cutover0.glm53.md
status: stable
generated: { by: model:glm-5.3, at: 2026-10-07 }
stale_after: 2026-10-21
sources:
  - resource: /design/kanata-source/handoff0.gpt61s.md
    title: Parent authorization and safe-cutover shape
  - resource: /design/kanata-source/services0.glm53.md
    title: Services-G declarations and preserve-rerender runbook (corrections commit oksqtpx / 1a536448)
  - resource: /design/kanata-source/preflight0.glm53.md
    title: Baseline this cutover was compared against
  - resource: /.test-agent/kanata-cutover/README.md
    title: Scoped rollback capture (updated restore procedure)
---

# Authorization and inputs

Parent approved live cutover under the user's existing authorization, after
Services G's corrected declarations (commit `1a536448`, jj `oksqtpx`:
unpinned sysuser, explicit `Restart=no`, empty `CapabilityBoundingSet=`,
per-config `KANATA_CONFIG_PRESERVE` write-once flag) passed their isolated
preserve-phase test and syntax checks. Executed from
[services0's runbook](/design/kanata-source/services0.glm53.md#how-the-live-handoff-installs-the-unit-without-regenerating-the-config)
and [handoff0's safe shape](/design/kanata-source/handoff0.gpt61s.md#safe-cutover-shape).

# Stage results

## Baseline comparison (preflight vs live, pre-cutover)

Config hashes (`d8138467…` main, `0052c3a7…` blueturn), both `/etc/kanata`
link targets, both wants-links, account (`990/985/input`), vendor rule
presence, package `install ok installed`: **all identical to preflight** —
no external drift, preflight baseline kept. Configs re-validated as
`_kanata`: both exit 0.

## Preserve rerender (durable roots, no execution)

```sh
ansible-playbook -i 'localhost,' -c local kanata.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True   # ok=105 changed=7
ansible-playbook -i 'localhost,' -c local kanata-blueturn.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True   # ok=103 changed=5
```

No kinata render. Verified post-render, pre-publish:

- **Config bytes and `/etc/kanata` link targets unchanged** (both hashes
  re-matched; the Kinesis exclusion stays authored-only, not adopted).
- Durable artifacts in `/etc/opt/kanata-main/` (no scratch paths anywhere
  in `links.json`): `kanata.service` (canonical name, `ExecStart=
  /usr/local/bin/kanata --cfg /etc/kanata/config.kbd`, `User/Group=
  _kanata`, `SupplementaryGroups=input`, explicit `Restart=no`, empty
  `CapabilityBoundingSet=`, full vendor hardening parity incl.
  `PrivateNetwork=true`/AF-denial/`IPAddressDeny=any`, `WantedBy=
  default.target`), `sysusers.d/kanata-main.conf` (id-less `u _kanata - …`
  + `m _kanata input`), `50-kanata-uinput.rules` (byte-exact vendor copy).
  BlueTurn unit: same hardening, `ExecStart=/usr/local/bin/kanata --cfg
  /etc/kanata/blueturn.kbd`, identity preserved (no alias).
- Current composed `install.sh` runs only `install-sysusers.sh` /
  `install-systemd.sh` / `install-links.sh` — **no apt lane invoked**; the
  stale `install-apt.sh`/`status-apt.sh` leaves remain in place
  deliberately (no prune).

## Cutover sequence (exact commands, in order)

```sh
sudo systemctl stop kanata.service kanata-blueturn.service   # both inactive
sudo mkdir -p /etc/sysusers.d
sudo ln -sfn /etc/opt/kanata-main/kanata.service         /etc/systemd/system/kanata.service
sudo ln -sfn /etc/opt/kanata-main/sysusers.d/kanata-main.conf /etc/sysusers.d/kanata-main.conf
sudo ln -sfn /etc/opt/kanata-main/50-kanata-uinput.rules /etc/udev/rules.d/50-kanata-uinput.rules
sudo systemd-sysusers /etc/sysusers.d/kanata-main.conf   # no-op: live account untouched
sudo systemctl daemon-reload
sudo udevadm control --reload-rules                      # rules only; no trigger, no reboot
sudo apt-get remove -y kanata                            # remove NOT purge NOT autoremove
sudo systemctl enable --force kanata.service             # repoint boot link off vendor path
sudo systemctl start kanata.service kanata-blueturn.service
```

**Mechanical correction (the one):** the first `apt-get remove kanata`
aborted at its interactive `[Y/n]` prompt — rerun with `-y`; nothing else
deviated. prerm's `deb-systemd-invoke stop kanata.service` was a no-op on
the already-stopped same-name unit, as predicted.

## Verification

| Check | Result |
|---|---|
| ActiveState/SubState ×2 | `active`/`running`, MainPIDs 235264 (main), 235263 (blueturn) |
| `/proc/<pid>/exe` ×2 | both → `/usr/local/bin/kanata` |
| Version | `kanata 1.12.1-prerelease-1` |
| Configs | hashes + link targets identical to preflight |
| Account | `uid=990(_kanata) gid=985(_kanata) groups=985(_kanata),114(input)` unchanged |
| Package | `deinstall ok config-files` (rc); `/usr/bin/kanata`, vendor unit, vendor rule gone |
| uinput | module loaded; owned rule at `/etc/udev/rules.d/50-kanata-uinput.rules` (→ `/etc/opt`); node `0660 root:input` |
| Listener | none — `ss -lntp` shows no sockets for either PID; sandbox lines intact in both units |
| Boot | both units `enabled`; main wants-link → `/etc/opt/kanata-main/kanata.service` (repaired off the vendor path); blueturn identity untouched |
| Journal | both: `v1.12.1-prerelease-1`, config valid, uinput devices created (event4/event21), clean loop entry, zero error lines |

Discovery parity: main registered **8/8 grabbable keyboard nodes** (Surface
Dial virtual, SteelSeries consumer, Kinesis Keyboard, vicinae, BS5P-ARC,
Keychron, ydotoold, WEIL WEILIANG). Two differences vs the Oct-1 journal
are **hardware state, not kanata**: the Kinesis *Consumer Control* kernel
node does not exist right now (`/proc/bus/input/devices` shows only the
Keyboard interface — a USB-enumeration difference from Oct 1), and the
iRig BlueTurn is absent/asleep (no node; its own instance waits via
`linux-continue-if-no-devs-found`). No `iRig` line appears in main's
current registrations.

# Residual manual tests (startup ≠ feel)

- **Caps tap-hold** (esc/lctl) typing feel under 1.12 — code-read says
  unchanged ([tap_hold_tracker is telemetry-only](/design/kanata-source/build0.glm53.md#e-backend-version-vs-the-deployed-configs-190--1121-prerelease-1)),
  fingers haven't confirmed.
- **Pedal reconnect**: wakes the blueturn instance and *proves the
  exclusion live under 1.12* (main must not register `iRig BlueTurn
  Keyboard` when the node appears).
- **Kinesis Consumer Control absence**: investigate on the hardware side
  (USB config/mode); not migration-blocking — the Keyboard node registers
  and Edge typing is remapped.

# What is now possible / impossible

**Possible now:** the deployed kanata lane is fully compfuzor-owned
(binary, canonical unit, account declaration, udev rule, configs) with
fresh-machine convergence; the TCP-capable binary is live under an intact
sandbox, so a future dial-precision bridge is a deliberate unit/transport
revision away rather than a rebuild. **Still impossible (deliberately):**
any listener (sandbox + no `--port` in either ExecStart), kinata, the
Kinesis exclusion going live, and dial policy/step/F-key changes — configs
are byte-identical to pre-migration.

# Rollback

Scoped capture and the phased restore procedure (including the `/etc`
same-name override handling and apt-reinstall preference) remain at the
[rollback README](file:///home/rektide/src/compfuzor/.test-agent/kanata-cutover/README.md).
Not needed: both instances run healthy on the source binary.
