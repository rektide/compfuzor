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
**dynamically allocated** by `useradd --system` in postinst, not static;
groups `_kanata` + `input` (114); home `/home/_kanata` (never created);
shell `/bin/zsh` (login.defs default). The pb comments call it "static" —
it is not; a machine rebuild without the package cannot recreate it, which
is exactly what a declared sysuser fixes.

# Inventory: what the replacement must own

| Artifact | Current owner | Replacement must |
|---|---|---|
| `kanata.service` unit file | Debian (`/usr/lib/systemd/system/kanata.service`), enabled via `/etc/systemd/system/default.target.wants/kanata.service` → Debian path | Own a unit at the same name from `/etc` (masks the vendor one) or a fresh name; parent direction: `SYSTEMD_SERVICE: kanata` preserves identity despite `NAME: kanata-main` |
| `_kanata` user + input group | Debian postinst (dynamic uid) | Declare via compfuzor's sysusers facility so it survives package removal and machine rebuilds |
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
