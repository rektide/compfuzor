---
type: BuildCheckpoint
title: kanata source build — tcp_server-capable binary at /usr/local/bin
description: First slice of the Debian→source kanata migration; build/install evidence and migration constraints, no cutover performed.
resource: /design/kanata-source/build0.glm53.md
status: draft
generated: { by: model:glm-5.3, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: https://github.com/jtroo/kanata/tree/2f84d17
    title: Built upstream revision (v1.12.1-prerelease-1-40-g2f84d17, origin/main)
  - resource: /design/surface-dial-layers/routing0.gpt61s.md
    title: Addendum establishing Debian kanata lacks --port/tcp_server
  - resource: /design/surface-dial-layers/syn0.gpt61s.md
    title: Parent synthesis naming the TCP-bridge constraint
  - resource: /kanata.src.pb
    title: Source-lane playbook (edited this slice)
  - resource: /design/surface-dial-input/kanata-assessment0.gpt61s.md
    title: Prior kanata merger analysis
---

# What this slice was and was not

User authorized source migration and Debian-package removal *in principle*;
this slice is the **first coherent step only**: inspect Debian build evidence
and package/service migration constraints, then build and install the source
binary — **without** stopping/restarting/reloading any input service, removing
the Debian package, replacing live configs, or grabbing/injecting input.
Active cutover waits for the parent checkpoint. Umbriel/dial config authoring
is explicitly out of scope (ownership stays with media-keys/surface-dial
producers).

The deployed state is unchanged: both services still run `/usr/bin/kanata`
(Debian 1.9.0+ds-1). Everything below is additive.

# What was built and installed

| Step | Command | Outcome |
|---|---|---|
| Playbook render | `ansible-playbook -i 'localhost,' -c local kanata.src.pb -e REPO_BYPASS=True -e PKGS_BYPASS=True -e APT_BYPASS=True -e BINS_RUN_BYPASS=True` | ok=98 changed=3 failed=0 |
| Build | `/usr/local/src/kanata-git/bin/build-rust.sh` → `cargo build --release --features tcp_server --locked` | Finished release in 42.05s; warnings only (redundant `homepage`, unused `radix_trie`, `nix` future-incompat) |
| Install | `sudo -n /usr/local/src/kanata-git/bin/install-rust.sh` | `copied .../target/release/kanata -> /usr/local/bin/kanata` — real file, 0755 root:root, 3174904 bytes |
| Version | `/usr/local/bin/kanata --version` | `kanata 1.12.1-prerelease-1` |
| TCP capability | `/usr/local/bin/kanata --help` | `-p, --port <PORT or IP:PORT>` present — the exact flag Debian 1.9.0 lacks |
| Main config check | `/usr/local/bin/kanata --check --cfg /etc/kanata/config.kbd` | `config file is valid`, exit 0 (parse-only, no device access) |
| BlueTurn config check | `/usr/local/bin/kanata --check --cfg /etc/kanata/blueturn.kbd` | `config file is valid`, exit 0 |

Both `--check` runs also log `kanata was compiled to never allow cmd`: the
`cmd` feature stays off (opt-in upstream), matching the no-cmd security
posture of the Debian build. `gilrs` compiled in — this tree carries upstream
gamepad-input support ([#2186]).

Bypass rationale: `REPO_BYPASS` avoided any checkout refresh (the deployment
checkout was already at the target revision — see lineage below);
`PKGS_BYPASS`/`APT_BYPASS` because `build-essential`, `pkg-config`,
`libudev-dev` were verified installed beforehand (state would have been a
no-op); `BINS_RUN_BYPASS` to drive the long build and root install manually.

## Source lineage — nothing local was disturbed

`~/archive/jtroo/kanata` is detached HEAD `2f84d17` = `main` =
`origin/main` (`v1.12.1-prerelease-1-40-g2f84d17`); jj working copy clean.
The gamepad commit `a02d65b` (#2186) is **upstream**, not a local patch — no
local commits exist beyond upstream main. The deployment checkout
`/usr/local/src/kanata-git/repo` is a **git worktree** of the archive
(`.git` → `.../archive/jtroo/kanata/.git/worktrees/repo`), on local btrfs —
no CIFS concern, no `CARGO_TARGET_DIR` override needed, and
`install-rust.sh`'s `target/<profile>` assumption holds unchanged. No fetch,
pull, reset, or checkout was run anywhere.

## Narrow playbook edit (committed separately, predecessor preserved)

[`kanata.src.pb`](/kanata.src.pb) gained two vars — no generator changes:

- `RUST_FEATURES: tcp_server` — explicit, though also in upstream defaults;
  Debian's omission is the whole motivation.
- `RUST_COPY: True` — copy a real file to `/usr/local/bin/kanata` instead of
  the default symlink through DIR (0770) and the `~/archive` worktree, which
  a non-root daemon under `ProtectHome` cannot traverse. The mechanism and
  its rationale are documented in the generator itself
  (`vars/common.yaml` install-rust.sh comment).

# Debian evidence: what `apt remove kanata` would and would not do

Read from maintainer scripts (`/var/lib/dpkg/info/kanata.*`), the shipped
unit, and `apt-get -s remove kanata` (simulation only):

| Concern | On `remove` (not purge) |
|---|---|
| Services | **prerm stops `kanata.service`** (`deb-systemd-invoke stop`) |
| Files removed | `/usr/bin/kanata`, `/usr/lib/systemd/system/kanata.service`, `/usr/lib/udev/rules.d/50-kanata-uinput.rules`, docs/examples |
| Files kept | `/etc/kanata/config.kbd` (dpkg conffile; live file is already compfuzor's symlink to `/etc/opt/kanata-main/kanata.kbd` — dpkg sees it as modified) |
| `_kanata` account | **kept**; deleted only on purge (`deluser --system`) |
| Reverse deps | none — `apt-get -s remove kanata` removes exactly one package |

The udev rule is load-bearing: it sets `/dev/uinput` to `0660 group=input`,
which (with `DeviceAllow`/`BindPaths` in the units) is how `_kanata` opens
uinput. **Whatever replaces the package must own an equivalent rule** or
input injection breaks for every kanata instance.

`_kanata` account facts (for the sysuser decision): uid 990 / gid 985 —
a **persistent ordinary system account** created by `useradd --system` in
postinst, with IDs allocated at install time. It is NOT a systemd
`DynamicUser=` ephemeral identity — the srv.pb comments' "static" means
*persistent account*, not *pinned UID*; groups `_kanata` + `input` (114);
home `/home/_kanata` (never created); shell `/bin/zsh` (login.defs
default). A declared sysuser preserves the current IDs on this box and
handles fresh creation on machine rebuilds.

# Inventory: what the replacement must own

| Artifact | Current owner | Replacement must |
|---|---|---|
| `kanata.service` unit file | Debian (`/usr/lib/systemd/system/kanata.service`), enabled via `/etc/systemd/system/default.target.wants/kanata.service` → Debian path | Own a unit at the same name from `/etc` (masks the vendor one) or a fresh name; parent direction: `SYSTEMD_SERVICE: kanata` preserves identity despite `NAME: kanata-main` |
| `_kanata` user + input group | Debian postinst (persistent system account, install-time UID allocation) | Declare via compfuzor's sysusers facility so it survives package removal and machine rebuilds |
| udev rule `50-kanata-uinput.rules` | Debian | Stage an equivalent rule (etc lane) |
| `/etc/kanata/config.kbd` | dpkg conffile + compfuzor LINKS symlink (`/etc/opt/kanata-main/kanata.kbd`) | Already compfuzor-owned; after removal dpkg's conffile bookkeeping is moot |
| `kanata-blueturn.service` | compfuzor (`/etc/opt/kanata-blueturn/`, enabled) | ExecStart retarget `/usr/bin/kanata` → `/usr/local/bin/kanata` |
| Binary | Debian `/usr/bin/kanata` (1.9.0) | Source binary `/usr/local/bin/kanata` (1.12.1-prerelease-1) — installed this slice, additive |

Live-config drift worth noting: deployed main config excludes **only**
`"iRig BlueTurn Keyboard"`; the pb (and the undeployed
[`kinata.srv.pb`](/kinata.srv.pb)) also declare the
`"Kinesis Freestyle Edge RGB Keyboard"` exclusion. kinata is declared but
not deployed — no kinata unit exists on the box. This is parent-owned
config territory; recorded here because a cutover touches the same file.

# What is now possible / impossible

**Now possible:**

- A TCP-server-capable kanata (`--port`) exists at a daemon-consumable path,
  on local disk, as a real file — prerequisite for the
  [routing0 addendum](/design/surface-dial-layers/routing0.gpt61s.md#addendum-deployed-kanata-is-not-tcp-ready)
  direction, without touching any running service.
- Parse-level confidence that both deployed configs are valid under
  1.12.1-prerelease-1 (four-version jump, zero parse errors).
- Repeatable rebuild: the src lane's bins regenerate; `build-rust.sh` +
  `install-rust.sh` are one command each; rollback is deleting one file.

**Still impossible until cutover (deliberately not done):**

- `--port` usable by a service: both live units carry `PrivateNetwork=true`,
  `RestrictAddressFamilies=AF_AX25` (+`~`), `IPAddressDeny=any` — a listener
  cannot exist inside them, and `_kanata` is not the desktop user. A TCP
  bridge needs revised transport/security arrangement per routing0's
  contract list (provenance, snapshot/authority, local security...).
- Runtime behavior identity: `--check` proves parse validity only. 1.12
  defaults differ from 1.9 in behavior-relevant ways (e.g. `zippychord` is a
  default feature upstream now) — no claim of identical feel is made.
- Anything requiring the Debian package gone: it is fully retained.

# Cutover proposal (for parent decision — not executed)

The prerm-stop/name-collision interplay drives the ordering. With a
compfuzor-owned unit at the *same name* (`/etc/systemd/system/kanata.service`
masks Debian's), `apt remove` prerm would stop **our** unit (same name),
then postrm's daemon-reload drops Debian's `/usr/lib` file while ours
survives in `/etc`. Coherent sequence:

1. Stage sysuser declaration + udev rule + compfuzor-owned units
   (`SYSTEMD_SERVICE: kanata` for main; blueturn unit already ours) with
   ExecStarts at `/usr/local/bin/kanata`; drop `kanata` from `PKGS` in
   main/blueturn/(future kinata) pbs so nothing reinstalls it.
2. Checkpoint gate (parent).
3. One maintenance window: stop instances, install/link units, `apt remove
   kanata` (prerm's stop is a no-op once already stopped; conffile symlink
   and `_kanata` account survive), start instances from source binary.
4. Post-checks: both services active, `journalctl` registering lines show
   same device set, uinput rule present, caps-tap/BlueTurn pedal manual test.

Unresolved decisions (parent owns): fresh unit names vs same-name masking;
whether kinata deploys before, with, or after cutover; whether main config
gets the Kinesis exclusion at cutover time; TCP bridge transport/security
design (separate work, needs service sandbox changes regardless); timing of
`apt remove` vs unit switch (steps 3's ordering is a proposal).

# Rollback (current package retained)

This slice changed nothing deployed. `sudo rm /usr/local/bin/kanata` returns
the box to its exact pre-slice state; the built artifact remains in
`/usr/local/src/kanata-git/repo/target/release/kanata` for re-install. For
the future cutover, rollback = repoint ExecStarts to `/usr/bin/kanata` +
`apt install kanata` (package still in the archive) — which is precisely why
removal is deferred behind the checkpoint.

# References

- [`routing0.gpt61s.md` addendum](/design/surface-dial-layers/routing0.gpt61s.md#addendum-deployed-kanata-is-not-tcp-ready) — the `--port` absence evidence that motivated this slice.
- [`syn0.gpt61s.md`](/design/surface-dial-layers/syn0.gpt61s.md) — parent synthesis; Kanata-TCP is one of two open routing paths.
- [`kanata.srv.pb`](/kanata.srv.pb) / [`kanata-blueturn.srv.pb`](/kanata-blueturn.srv.pb) / [`kinata.srv.pb`](/kinata.srv.pb) — the three instances and their unit sandboxes.
- Upstream [#2186] gamepad input — present in the built tree.
- Scratch command log: `.test-agent/kanata-source/README.md` (gitignored).

[#2186]: https://github.com/jtroo/kanata/pull/2186

# Addendum: lineage proof, runtime-facility audit, full prerequisite inventory (2026-10-06, post-build)

Raised at parent review: distinguish local vs upstream gamepad work, verify
what the binary initializes for no-gamepad/no-port configs, inventory ALL
package-owned prerequisites (not just the unit), and make 1.9→1.12 behavior
deltas explicit. All evidence below is read-only; nothing deployed changed.

## A. Built revision is pure upstream — proven against live GitHub

- [PR #2186] was **merged by jtroo into `jtroo:main` on Sep 28, 2026**,
  merge commit `a02d65b` — byte-identical to the archive commit. The gamepad
  work is upstream (author philocalyst, owner-reviewed and approved).
- Committer audit of all 40 commits `v1.12.1-prerelease-1..2f84d17`:
  34× `noreply@github.com`, 5× `jtroo@roselily.ca`, 1×
  `j.andreitabs@gmail.com` — **zero local committers** (a local cherry-pick
  or re-commit would carry a local committer identity).
- `origin/main` reflog shows a genuine fetch from origin storing `2f84d17`;
  `main...origin/main` = 0/0. jj working copy empty at that parent.
- Conclusion: **no local or unmerged feature work exists in the built tree**;
  nothing was dropped or reset, and the exact built revision is
  `2f84d17` (`v1.12.1-prerelease-1-40-g2f84d17`, upstream main).

## B. What the built binary initializes for the deployed configs

| Facility | Init condition ([`src/main.rs`](https://github.com/jtroo/kanata/blob/main/src/main.rs) 203-233) | Status under preserved sandbox |
|---|---|---|
| TCP server + notification loop | only `if let Some(args.tcp_server_address)` — no `--port`, nothing starts | dormant; `IPAddressDeny=any` + AF denial hold regardless |
| Gamepad/gilrs backend | `start_gamepad_handling_if_configured` returns before touching gilrs unless config declares `defgamepad` ([mod.rs:1206](https://github.com/jtroo/kanata/blob/main/src/kanata/mod.rs#L1206): `gamepad_config` else-return) | deployed configs have no gamepad vocabulary → never spawns |
| `cmd` execution | `#[cfg(feature = "cmd")]` — not compiled | startup log: "compiled to never allow cmd" |
| Clipboard helpers (child spawn, `clipboard.rs` `run_cmd_get_stdout`; arboard) | action-time only | no clipboard actions in deployed configs |
| `sd_notify` Ready | called unconditionally; `Ok(false)` when `NOTIFY_SOCKET` unset | inert under Type=simple |
| Processing loop, inotify `/dev/input` watcher | always | same shape as 1.9, empirically sandbox-compatible (Debian 1.9 runs under the identical unit) |

gilrs is compiled in (hard dep; Linux backend is libudev) but dormant.
Should `defgamepad` ever be used: gilrs-core 0.6.8's Linux backend uses udev
**enumeration** + a polling loop (`udev_enumerate_*`; `POLL_TIMEOUT` in
kanata's `gamepad/source.rs`) — no udev monitor/netlink found, and
`/dev/input` is already bound read-only with `char-input` allowed, so it
would likely fit the existing sandbox; verify when actually introduced.

**Verdict: no new runtime facility initializes for the deployed configs —
no concrete sandbox conflict, no dehardening and no sandbox revision needed
for cutover. The TCP capability is compile-time present, runtime dormant.**

## C. Complete package-owned prerequisite inventory

`dpkg -L kanata` non-doc paths are exhaustive; dpkg triggers: awaited/interested both empty.

| Package path | Kind | Effect when lost on `remove` | Durable owner after cutover |
|---|---|---|---|
| `/usr/bin/kanata` | binary | immediate | `/usr/local/bin/kanata` (this slice) |
| `/usr/lib/systemd/system/kanata.service` | vendor unit | file gone immediately; `default.target.wants` enable-symlink dangles | compfuzor same-name `/etc` unit (Services G prepares) |
| `/usr/lib/udev/rules.d/50-kanata-uinput.rules` | udev rule | **next udev reload/reboot**, not immediately (see D) | decision needed: own rule vs documented reliance (D) |
| `/etc/kanata/config.kbd` | conffile | kept on remove | already compfuzor symlink |

No sysusers.d, tmpfiles.d, modules-load.d, D-Bus, or hwdb entries ship in
the package — nothing else exists to migrate. The `_kanata` account is
postinst-created (kept on remove; see main doc).

## D. The real uinput permission/boot chain (and the reboot-lifetime caveat)

Current `/dev/uinput`: `0660 root:input` (stat). Rules granting group-input
access on this box today:

| Rule | Owner | Grants `_kanata`? |
|---|---|---|
| `50-kanata-uinput.rules` | kanata pkg | yes (GROUP=input, MODE=0660) — redundant while installed |
| `80-uinput.rules` | **ydotool package** | yes (GROUP=input, MODE=0660, static_node) |
| `60-sunshine.rules` | compfuzor sunshine deployment | yes (GROUP=input, MODE=0660) |
| `60-steam-input.rules` | steam-devices pkg | no (uaccess seat-ACL only — irrelevant to `_kanata`) |
| `/etc/udev/rules.d/10-uinput.rules` | compfuzor `surface-dial.src.pb` | no (uaccess/udev-acl only) |

Boot-time module loading: `/etc/modules-load.d/sunshine-git.conf` and
`apollo-git.conf` (both `uinput`) plus `modprobe@uinput.service`
Wants/After in every kanata unit (including compfuzor's blueturn/kinata
templates). Static node: `modules.devname` carries `uinput c10:223`
(devtmpfs).

**Reboot-lifetime caveat:** on `apt remove`, the in-memory udev ruleset and
the current node's mode persist until udev reload/reboot — kanata's
prerm/postrm never reload udev (postrm only runs systemd `daemon-reload`).
So a passing service check after removal proves nothing about boot
durability. With today's package set the next boot still yields 0660
root:input via **ydotool's** rule (and sunshine's) — but those are
discretionary siblings. The kanata lane should either declare its own udev
rule or explicitly document reliance on ydotool's before cutover; that
decision belongs to Services G's offline pb declarations (no sibling pb was
modified by this slice).

## E. Backend version vs the deployed configs (1.9.0 → 1.12.1-prerelease-1)

- Parse: both configs valid (`--check` exit 0). `linux-dev-names-include`/
  `exclude` remain exact device-name lists per `docs/config.adoc`; the new
  `linux-dev` option is additive. `process-unmapped-keys` and
  `linux-continue-if-no-devs-found` accepted — BlueTurn's no-device startup
  path is unaffected at parse level.
- Breaking `fix!` commits since v1.9.0 — switch repeatability (#2004),
  custom-action queueing (#2003), sequence vkey priority (#1712) — touch
  features **absent from both deployed configs** (no `switch`, `defseq`, or
  queued custom-action vocabulary).
- `zippychord`: compiled in but config-gated — engaged only by config
  options the deployed configs don't set; no timing change.
- `tap_hold_tracker` (pulled into keyberon by `tcp_server`): telemetry
  storage for push messages only ("Only stores data when the feature is
  enabled", `keyberon/src/layout.rs:144`); no timing decision reads it;
  inert without TCP clients. **Building with tcp_server does not alter
  tap-hold behavior.**
- Device ownership: this slice changed no config — include/exclude sets are
  identical; the cutover proposal makes no device-ownership change.
- Honest limit: parse-level and code-reading evidence. Runtime feel is
  untested until a cutover window's manual checks (caps tap-hold, pedal
  pgup/pgdn + meta-hold); 33 keyberon `layout.rs` commits since v1.9.0
  (mostly mouse/mwheel) are the residual uncertainty.

## F. Repo bookkeeping note (resolved)

jj change `ynzvxrwq` had gone divergent — a change-ID race between two
concurrent sessions: `/0` (`b4b278a1`) the parent's kernel-bins commit,
`/1` (`3eb2146d`) this slice's checkpoint. The parent resolved it with
`jj metaedit --update-change-id`: the build checkpoint now stands as
`kmktxxqw` / commit `c2469324`. No duplicate/abandon was used; no content
was discarded and no source revision was reset.

## G. Checkpoint acceptance (parent review, 2026-10-06)

Parent reviewed the code and the cited evidence (main.rs/mod.rs runtime
gates, prerm/postrm semantics) and accepted the source
artifact/capability checkpoint. Decisions recorded:

- **udev**: OWN rule in main, at exactly `/etc/udev/rules.d/
  50-kanata-uinput.rules` — no reliance on discretionary siblings.
- **Unit identity**: canonical same-name main `/etc` unit.
- **Scope holds**: no kinata adoption; no Kinesis-exclude change in the
  live main config; no TCP listener yet (sandbox preserved).
- **Authorization status**: the future cutover carries *actual* user
  authorization, not merely in-principle — the remaining gate is internal
  handoff (Services G declarations ready), after which this session
  continues with cutover.

Remaining ownership/status statements in this document stay as the
first-slice snapshot (dated 2026-10-06) unless superseded above.

The gate named above is now closed on the declaration side: the services
slice landed in [services0.glm53.md](/design/kanata-source/services0.glm53.md)
(unit, sysusers identity, uinput rule, helper retargets; scratch-fenced,
no live change).

