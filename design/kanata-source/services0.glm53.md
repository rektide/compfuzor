---
type: ServicesCheckpoint
title: kanata persistent services — source-lane declarations ready, no cutover
description: Services-G preparation slice; canonical unit, single sysusers identity owner, uinput udev rule, helper retargets, and the regression fence, all rendered offline.
resource: /design/kanata-source/services0.glm53.md
status: draft
generated: { by: model:glm-5.3, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: /design/kanata-source/brief0.gpt61s.md
    title: Migration intent and ownership checkpoints
  - resource: /design/kanata-source/build0.glm53.md
    title: Build checkpoint, prerm/udev evidence, parent acceptance §G
  - resource: /kanata.srv.pb
    title: Main service playbook (edited this slice)
  - resource: /kanata-blueturn.srv.pb
    title: BlueTurn helper (edited this slice)
  - resource: /kinata.srv.pb
    title: Kinesis helper (edited this slice, still undeployed)
  - resource: /tasks/compfuzor/gen_sysusers.tasks
    title: Sysusers generator (identity facility used as-is)
  - resource: /usr/lib/systemd/system/kanata.service
    title: Packaged unit whose hardening main mirrors
---

# What this slice is and is not

The parent accepted the build checkpoint ([build0 §G](/design/kanata-source/build0.glm53.md#g-checkpoint-acceptance-parent-review-2026-10-06))
and authorized the services declarations: canonical same-name main unit,
main as single identity owner, and a kanata-owned uinput udev rule. This
slice is exactly that **offline preparation**: the three persistent
playbooks now declare the full source-lane deployment, verified by a
regression test that renders into scratch domain roots only.

**Nothing live changed.** No unit was linked or enabled, no
daemon-reload, no sysusers run, no udev reload, no service stop/start, no
package removal, and — the subtle one — no regeneration of the live
config: a live render would overwrite `/etc/opt/kanata-main/kanata.kbd`
(the symlink target of `/etc/kanata/config.kbd`) with the authored body,
which still carries the not-yet-adopted Kinesis exclusion
([build0](/design/kanata-source/build0.glm53.md) live-config drift note).
Cutover, including `apt remove kanata`, stays behind the parent gate.

# Declarations

## [`kanata.srv.pb`](/kanata.srv.pb) — main owns unit, identity, and rule

- **No `PKGS`**: nothing reinstalls the Debian package. The whole
  deployment is compfuzor-owned once the package leaves.
- **`SYSTEMD_SERVICE: kanata` + `SYSTEMD_ALIAS: false`**: renders the
  canonical `kanata.service` (not `kanata-main.service`), replacing the
  packaged unit *at the same name* from `/etc`, with no alias competing
  for it. This is the parent-approved same-name masking shape from
  [build0 §Cutover](/design/kanata-source/build0.glm53.md#cutover-proposal-for-parent-decision-not-executed).
- **`SYSTEMD_SYSUSER: True` + `SYSUSERS`**: single declarer of `_kanata`.
  The fragment is deliberately id-less — `u _kanata - "Kanata daemon"
  /nonexistent /usr/sbin/nologin` plus `m _kanata input`. systemd-sysusers
  never touches an existing name, so the persistent account the package
  created (`useradd --system` postinst, install-time ids 990/985 here —
  *not* DynamicUser lifecycle) survives removal verbatim as a no-op,
  with **no machine-specific pinning**: fresh machines allocate normal
  system ids. The `u` line implies the same-name primary group — a
  separate `g _kanata` spec is impossible by design (the renderer
  declares one line per name), and none is needed.
- **Unit body**: mirrors the retired
  `/usr/lib/systemd/system/kanata.service` with the helpers' schema:
  `User=_kanata`/`Group=_kanata`/`SupplementaryGroups=input` spelled out,
  `ExecStart=/usr/local/bin/kanata --cfg /etc/kanata/config.kbd`
  ([`GLOBAL_BINS_DIR`](/vars/common.yaml), where
  [`kanata.src.pb`](/kanata.src.pb)'s `RUST_COPY: True` installs the real
  file), an explicit `Restart=no` (quoted in YAML — a bare `no` is
  `False`, which the unit template drops), the packaged unit's empty
  `CapabilityBoundingSet=` line, and `WantedBy=default.target` retained.
- **`ETC_FILES` + `LINKS` for `50-kanata-uinput.rules`**: byte-exact copy
  of the vendor rule (`KERNEL=="uinput", MODE="0660", GROUP="input",
  OPTIONS+="static_node=uinput"`, 0644) linked to the same basename in
  `/etc/udev/rules.d`. The `/etc` copy masks the vendor file while the
  package is installed and survives `apt remove`; without it, the next
  udev reload/reboot would leave `/dev/uinput` at the mercy of
  discretionary siblings (ydotool's `80-uinput.rules`, sunshine's rule).
  Kanata owns its dependency instead. Applied by the links lane plus a
  `udevadm` reload/trigger (or reboot) **at cutover** — not live.
  `Wants=/After=modprobe@uinput.service` stays the generic module
  bootstrap; the package ships no modules-load file to replace.
- **Config body byte-for-byte unchanged** — including the authored
  Kinesis exclusion, which stays *authored only*. The live main config is
  not touched by this slice, and the exclusion is not adopted.
- **`KANATA_CONFIG_PRESERVE` once-flag on all three configs**: each
  `kanata.kbd` ETC_FILES entry carries `once: "{{ KANATA_CONFIG_PRESERVE
  | default(false) | bool }}"` — [fs_hierarchy](/tasks/compfuzor/fs_hierarchy.tasks)'s
  per-item write-once (a per-file property, *not* an ETC_PROP-level
  once). Authored content is unchanged and default renders stay
  authoritative over the file; a cutover rerender with the flag set
  skips writing the existing bytes (live topology preserved) while every
  other declared artifact — units, sysusers fragment, udev rule, install
  composites, links catalog — refreshes to current source-lane state.

## [`kanata-blueturn.srv.pb`](/kanata-blueturn.srv.pb), [`kinata.srv.pb`](/kinata.srv.pb) — helpers consume

- `PKGS: [kanata]` removed; `ExecStart` switched
  `/usr/bin/kanata` → `/usr/local/bin/kanata` (same staged configs,
  `/etc/kanata/blueturn.kbd` / `kinata.kbd`).
- Identity **consumed, not declared**: `User=/Group=_kanata` +
  `SupplementaryGroups: input` reference what main declares; no
  `SYSUSERS`/`SYSTEMD_SYSUSER` of their own. The repo-wide
  single-declarer invariant is test-enforced.
- `SYSTEMD_ALIAS: false` stays load-bearing: the `-blueturn`/`-kinata`
  names must never alias onto the canonical `kanata.service` main owns.
- Hardening untouched — same schema as main (test-compared key-for-key).
  kinata remains declared-but-undeployed; no kinata unit exists on the
  box and none is created here.

# Generated artifacts (scratch-render exhibit)

`kanata.service` renders to the packaged unit's shape; the deliberate
deltas against `/usr/lib/systemd/system/kanata.service`:

| Delta | Why |
|---|---|
| `+Group=_kanata`, `+SupplementaryGroups=input` | static identity + input access spelled out (packaged unit relied on primary-group/passwd membership) |
| `ExecStart` → `/usr/local/bin/kanata` | source lane |
| `+RestartSec=5` | compfuzor default, inert under `Restart=no` |

`Restart=no` and the empty `CapabilityBoundingSet=` are carried
explicitly (quoted/empty-string YAML, since the unit template skips only
literal `False`), so hardening parity with the packaged unit is
line-for-line complete.

Everything else is line-for-line the packaged hardening, including
`PrivateNetwork=true`, `RestrictAddressFamilies=AF_AX25` + `~AF_AX25`
(the deny-everything idiom), `IPAddressDeny=any`, `DevicePolicy=strict`,
`ProtectSystem=strict`, `SystemCallFilter=@system-service` — **the TCP
capability changes none of it**: binary capability and listener policy
are separate, and a listener needs a deliberate sandbox revision
([build0 §B](/design/kanata-source/build0.glm53.md#b-what-the-built-binary-initializes-for-the-deployed-configs)).

The sysusers fragment (`DIR/etc/sysusers.d/kanata-main.conf`):

```ini
u _kanata - "Kanata daemon" /nonexistent /usr/sbin/nologin
m _kanata input
```

Main's link plan carries four records — config, udev rule, unit, and
sysusers fragment — each applied by its own install lane at cutover.

# Verification

[`tests/integration/kanata_source_services.test.py`](/tests/integration/kanata_source_services.test.py)
renders all three playbooks with `SRVS_DIR`/`ETCS_DIR` redirected into
`.test-agent` scratch and every side-effecting phase bypassed
(`PKGS`/`APT`/`SYSTEMD_THUNK`/`BINS_RUN`/`GLOBAL_BINS`), then asserts:

- canonical unit: `kanata.service` rendered, **no** `kanata-main.service`,
  no `Alias=`, `WantedBy=default.target`, packaged Description;
- identity: exact sysusers fragment (id-less `u _kanata -` + `m input`);
  repo-wide scan proving exactly one `_kanata` declarer (`kanata.srv.pb`);
  helpers declare nothing;
- no Debian dependency: no `kanata` in any `PKGS*` of the three; no apt
  lane (`install-apt.sh`/`status-apt.sh`) in any rendered `bin/`;
- source binary + protection: all three `ExecStart`s on
  `/usr/local/bin/kanata`; helper hardening key-set equal to main's;
  explicit `Restart=no` and empty `CapabilityBoundingSet=` present; no
  `AF_INET`/`AF_UNIX`/`IPAddressAllow`/listener vocabulary anywhere
  (sandbox not loosened);
- udev rule: byte-exact vendor copy at 0644 (also cross-checked against
  the live vendor file, failing if upstream's copy changes), with the
  `/etc/udev/rules.d/50-kanata-uinput.rules` link record present;
- config bodies: authored main exclusion block (both device names) and
  keymap lines intact; blueturn's rendered config byte-identical to the
  live deployed one; helper include blocks intact;
- **`KANATA_CONFIG_PRESERVE` regression** (both directions, all three
  playbooks): replace the rendered config with a sentinel
  current-topology body → a default rerender restores authored bytes
  (renders stay authoritative) → sentinel again + corrupted unit +
  deleted installer → a preserve-flag rerender retains the sentinel
  **byte-exactly** while the unit is restored, the install composites
  regenerate, and no apt leaf (`install-apt.sh`/`status-apt.sh`) or
  `install-apt` reference exists anywhere in `bin/`;
- **live fence**: `/etc/opt/kanata-*`, `/srv/kanata-*`, `/etc/kanata`,
  `/etc/systemd/system` kanata/kinata entries, `/etc/sysusers.d`,
  `/etc/udev/rules.d` `*kanata*` entries, and the `_kanata` passwd/group
  records snapshotted before and compared after every render phase —
  zero drift, no new paths.

Result (2026-10-07):

```
$ python3 tests/integration/kanata_source_services.test.py
ok: kanata source services (canonical unit, one identity declarer, no
Debian dependency, owned uinput rule, configs unchanged,
config-preserve rerender verified, live deployment untouched)
```

`ansible-playbook --syntax-check` passes for all three playbooks.
Commits: `zomuttw` (declarations + test), `ttolwwx` (udev rule slice).

# How the live handoff installs the unit WITHOUT regenerating the config

A plain live render would rewrite `/etc/opt/kanata-main/kanata.kbd` (the
symlink target of `/etc/kanata/config.kbd`) with the authored body —
adopting the un-decided Kinesis exclusion. The live config's **current
topology is preserved exactly**; no Kinesis decision is needed or
implied here. Copying unit files out of scratch is also not the shape:
the live deployment's *composites* (`install.sh` lanes, links catalog)
would stay stale — still composing the Debian apt installer the source
playbooks no longer declare. The native primitive is the per-file `once`
flag (above): the cutover **rerenders main and BlueTurn into their real
durable roots with the flag set**, refreshing all declared state while
the existing config bytes skip write:

```sh
ansible-playbook -i 'localhost,' -c local kanata.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True
ansible-playbook -i 'localhost,' -c local kanata-blueturn.srv.pb \
  -e KANATA_CONFIG_PRESERVE=True -e BINS_RUN_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e PKGS_BYPASS=True \
  -e APT_BYPASS=True -e GLOBAL_BINS_BYPASS=True   # kinata: NO live render
```

Prep only: the render writes material and `links.json`; no installer
runs, no unit starts, and no `/etc` links publish (links.mjs only runs
inside install scripts). Then publish the durable links and reload:

```sh
sudo ln -sfn /etc/opt/kanata-main/kanata.service               /etc/systemd/system/kanata.service
sudo ln -sfn /etc/opt/kanata-main/sysusers.d/kanata-main.conf  /etc/sysusers.d/kanata-main.conf
sudo ln -sfn /etc/opt/kanata-main/50-kanata-uinput.rules       /etc/udev/rules.d/50-kanata-uinput.rules
sudo systemd-sysusers /etc/sysusers.d/kanata-main.conf   # no-op against the live account
sudo systemctl daemon-reload
sudo udevadm control --reload-rules                      # rules only; no device trigger, no reboot
```

The rerender does **not** prune old undeclared leaves (the PKGS-era
`install-apt.sh`/`status-apt.sh`/`install-service.sh` and the inert
pre-migration `kanata-main.service`): compfuzor creates declared state;
removing undeclared files is a separate deliberate decision outside this
migration. Unit enable/start and `apt remove kanata` (whose prerm stops
the canonical `kanata.service` by name) stay in the parent's cutover
sequence per [handoff0](/design/kanata-source/handoff0.gpt61s.md). This
slice runs none of it; the cutover executor does, after parent approval.

# What became possible / impossible

**Possible now:** the whole source lane is declarative and test-fenced —
unit identity, account survival, uinput permissions, and helper
retargets need no hand-editing at cutover; fresh-machine convergence
exists for an account the package created ad-hoc; and the
`KANATA_CONFIG_PRESERVE` rerender lets the cutover refresh current
declared installer/catalog state in the durable roots — no scratch-path
copying, no stale apt composites — while the live config bytes stay
exactly as deployed.

**Still impossible (deliberately):** any live state change (unit/sysusers/
udev/config), kinata deployment, the Kinesis exclusion going live, and
any TCP listener — the sandbox is unchanged and a bridge needs its own
design ([routing0](/design/surface-dial-layers/routing0.gpt61s.md)).

# Open questions (parent-owned)

- **Kinesis exclusion timing** — decide separately from this migration:
  adopt the split (deploy kinata) or drop the exclusion from the authored
  body; until then live main config ≠ authored (default renders fenced,
  preserve renders explicit).
- **Stale undeclared leaves in live deployments** — the preserve-flag
  rerender refreshes every *declared* artifact (composites, links
  catalog included) but deliberately does not prune undeclared files:
  the PKGS-era `install-apt.sh`/`status-apt.sh`/`install-service.sh` and
  the inert pre-migration `/etc/opt/kanata-main/kanata-main.service`
  remain until a separate deliberate removal decision; none is promised
  here.
- **Undeployed `kinesis/kanata/**` experiments** still declare
  `PKGS: [kanata, python3]` — flagged only (not this slice's files);
  they would reinstall the package if ever deployed.
- **`WantedBy=default.target`** retained for packaged parity; whether to
  normalize to `multi-user.target` is a separate, deliberate change.

# Cross-references

- [`handoff0.gpt61s.md`](/design/kanata-source/handoff0.gpt61s.md) —
  the parent decisions this slice implements (canonical identity, owned
  uinput rule, persistent-account sysusers, config preservation, sandbox
  retention, remove-not-purge) whose safe-cutover shape the
  preserve-rerender runbook serves.
- [`brief0.gpt61s.md`](/design/kanata-source/brief0.gpt61s.md) —
  authorization scope and the three-checkpoint structure this slice
  completes the middle of.
- [`build0.glm53.md`](/design/kanata-source/build0.glm53.md) — built
  binary evidence, prerm/postrm semantics, udev-chain analysis (§D
  deferred the rule decision to this slice), and §G parent acceptance.
- [`routing0.gpt61s.md`](/design/surface-dial-layers/routing0.gpt61s.md)
  — the TCP motivation that stays intentionally unserved by this slice.
- [`skill/systemd.md`](/skill/systemd.md) — unit generation semantics
  (`SYSTEMD_SERVICE` naming, `SYSTEMD_ALIAS`, install-script naming)
  relied on here.
- [`.design/gen-user/init.md`](/.design/gen-user/init.md) /
  [`gen_sysusers.tasks`](/tasks/compfuzor/gen_sysusers.tasks) — the
  sysusers facility whose declare/consume split this adopts.
- [`kanata.src.pb`](/kanata.src.pb) — owns the binary this slice points
  at; `RUST_COPY: True` is why `/usr/local/bin/kanata` is a real,
  daemon-readable file.
