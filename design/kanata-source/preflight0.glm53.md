---
type: PreflightCheckpoint
title: cutover preflight — identity-level checks and additive rollback capture
description: Verified the source binary and configs as the actual _kanata account and captured byte-exact rollback artifacts; no live state touched.
resource: /design/kanata-source/preflight0.glm53.md
status: draft
generated: { by: model:glm-5.3, at: 2026-10-07 }
stale_after: 2026-10-21
sources:
  - resource: /design/kanata-source/build0.glm53.md
    title: Accepted build checkpoint this preflight extends
  - resource: /.test-agent/kanata-cutover/README.md
    title: Rollback capture inventory and restore procedure
---

# Context

Independent preflight while Services G applies portability/security/
preserve-flag corrections to the sibling declarations. Still **no cutover,
no removal, no service reload**. The [build0 checkpoint](/design/kanata-source/build0.glm53.md)
stands as accepted; this document adds two narrow preflight results and
records the parent's sequencing decisions for the future window. Build0 and
the source-lane docs need no further revisions.

# Identity-level config checks (the copy/identity permission concern)

Prior `--check` runs (build0) executed as the desktop user; the open
question was whether the *actual service identity* can execute the
root-owned copy at `/usr/local/bin/kanata` and read the configs through
the `/etc/kanata` links. Run as `_kanata`, parse-only, no grabs:

```console
$ sudo -n -u _kanata /usr/local/bin/kanata --check --cfg /etc/kanata/config.kbd
[INFO] kanata v1.12.1-prerelease-1 starting
[INFO] validating config only and exiting
[INFO] config file is valid            # exit 0

$ sudo -n -u _kanata /usr/local/bin/kanata --check --cfg /etc/kanata/blueturn.kbd
[INFO] config file is valid            # exit 0
```

**Result: the identity concern is answered.** `/usr/local/bin/kanata` is
`-rwxr-xr-x root:root` (RUST_COPY install); `_kanata` executes it and
resolves both config symlinks. No listener was opened, no device touched.

# Additive rollback capture

Captured 2026-10-07 into `.test-agent/kanata-cutover/backup/` with
SHA256-verified byte fidelity (capture hash == live hash for every
artifact): Debian binary, vendor `kanata.service`, compfuzor
`kanata-blueturn.service` unit bytes, `50-kanata-uinput.rules`, and both
staged keymap files. Exact link topology recorded — including the fact
that the canonical main enable symlink currently points at the **vendor**
unit path (`default.target.wants/kanata.service → /usr/lib/systemd/system/
kanata.service`). Account facts captured scoped to `_kanata` only (uid 990,
gid 985, group `input` 114; no passwd/group/shadow dumps). Package identity:
`kanata 1.9.0+ds-1 install ok installed`. The capture is purely additive;
restore procedure is documented there and **not executed**. Full inventory:
[rollback capture README](file:///home/rektide/src/compfuzor/.test-agent/kanata-cutover/README.md).

# Sequencing decisions recorded for the future window (parent direction)

1. **Sysuser: unpinned ID.** The source-account sysuser declaration uses
   normal allocation — on this box it preserves the live `_kanata`
   (990/985) rather than pinning numbers.
2. **`CapabilityBoundingSet=` empty on all three units** (matches the
   vendor unit's hardening).
3. **Explicit `Restart=no`** on all three (deliberate, not inherited
   default).
4. **`KANATA_CONFIG_PRESERVE` once-guard** (per-config) enables the actual
   durable main+BlueTurn playbook re-render with *all* execution/thunk/
   package bypasses: keymaps stay byte-identical while the CURRENT
   composed installers/catalogs are regenerated — stale composites
   otherwise risk reinstalling the Debian package. **Awaiting parent
   approval before that live render; not performed in this preflight.**
5. **Enable-symlink repair:** after the same-name `/etc` unit switch,
   `systemctl enable --force kanata.service` alone repairs the durable
   boot reference currently aimed at the vendor path.
6. **`remove`, NOT `purge`:** a later purge of the removed rc-state Debian
   package would still `deluser _kanata` (postrm). Removal keeps the
   account and conffile.
7. **No pruning of inert old leafs** during the window.

# What remains open before the window

Services G's corrected declarations (portability/security/preserve flags)
and parent approval of the `KANATA_CONFIG_PRESERVE` re-render. Runtime
manual tests (caps tap-hold, pedal behavior) remain cutover-window work
per build0 §E's honest limit.

# Cross-references

- [build0.glm53.md](/design/kanata-source/build0.glm53.md) — accepted build checkpoint; §G records the checkpoint-acceptance decisions this preflight operates under.
- [`kanata.src.pb`](/kanata.src.pb) — production binary build lane (header updated post-acceptance).
- [Rollback capture](file:///home/rektide/src/compfuzor/.test-agent/kanata-cutover/README.md) — byte-exact artifacts, link topology, restore procedure.
- [routing0.gpt61s.md](/design/surface-dial-layers/routing0.gpt61s.md#addendum-deployed-kanata-is-not-tcp-ready) — the TCP direction this source build unblocks; no listener enabled in this slice.
