---
type: Design
title: build-confext inputs and output contract — corrections and a builder shape for systemd-iface*
description: Corrects the confext-specific upstream facts in archaeology0, traces the systemd-iface-static-only and extra-addr bytes/destinations/discovery inputs end to end, establishes what the catalog does and does not record, and bounds directory vs filesystem-image vs DDI output choices for a build-only confext step.
resource: https://github.com/rektide/compfuzor/blob/main/design/confext/build-inputs1.fx.md
tags: [compfuzor, confext, systemd, links, build-lane, iface]
status: draft
generated: { by: llm:glm53flashmax (GLM 5.3 Flash Max via OpenCode), at: 2026-09-26 }
verified: { by: none, at: null }
stale_after: 2026-12-26
sources:
  - id: predecessor
    resource: /design/confext/archaeology0.fx.md
    title: archaeology0.fx — FS_CONTAINERD arc (corrected in situ by this doc)
  - id: runtime-wave
    resource: /design/confext/runtime0.sm.md
    title: runtime0.sm — runtime lifecycle seams (independent companion wave)
  - id: systemd-source
    resource: ~/archive/systemd/systemd (v261-1244-g8f4cd7de43)
    title: Local systemd checkout — confext paths, metadata, mutability read from source
  - id: mkosi-source
    resource: ~/archive/systemd/mkosi (v27-12-g938d6a1c)
    title: Local mkosi checkout — extension-release writer and confext repart definitions
  - id: live-deployment
    resource: /etc/opt/systemd-iface-extra-addr-eno1 (read-only inspection)
    title: Rendered deployment tree and links.json used as ground truth
---

# build-confext inputs: corrections and a builder contract for the iface playbooks

Underlying model: **GLM 5.3 Flash Max** (suffix `fx`). Research only — no
implementation, no host mutation, no activation. Priority per the operator:
**building confext only**; installation/activation tooling is future work.

## 1. Corrections to [`archaeology0.fx.md`](/design/confext/archaeology0.fx.md) §5

The predecessor's §5 read systemd's *sysext* documentation and generalized to
confext. Reading the actual confext implementation
([`src/sysext/sysext.c`](~/archive/systemd/systemd/src/sysext/sysext.c) — one
multicall binary dispatching on argv[0], `sysext.c` L3282
`arg_image_class = invoked_as(argv, "systemd-confext") ? IMAGE_CONFEXT : …`,
plus `src/shared/discover-image.c`, `src/basic/os-util.c`,
`src/shared/extension-util.c`) changes five claims:

| # | archaeology0 said | Verified fact (confext-specific) | Evidence |
|---|---|---|---|
| 1 | Search paths `/etc/extensions/`, `/run/extensions/`, `/var/lib/extensions/` (quoted from `systemd-sysext.xml`) | **confext uses different dirs**: `/run/confexts` (symlink placement), `/var/lib/confexts` (main image place), `/usr/local/lib/confexts`, `/usr/lib/confexts` (vendor places). There is **no `/etc/confexts`**. sysext keeps the `extensions/` set. | [`discover-image.c` L74–101](~/archive/systemd/systemd/src/shared/discover-image.c); `.confext`/`.sysext` suffix table L107–108 |
| 2 | Identity via `/usr/lib/extension-release.d/extension-release.<NAME>` | **confext identity lives under `/etc/`**: `etc/extension-release.d/extension-release[.NAME]` vs sysext's `usr/lib/extension-release.d/…`. Fallback when the exact name is missing: any `extension-release.*` file in the dir carrying the `user.extension-release.strict` xattr. | [`os-util.c` L41–46, L107–108, L147–162, L248–265](~/archive/systemd/systemd/src/basic/os-util.c) |
| 3 | (implicit) sysext metadata keys apply | confext has its own keys: **`CONFEXT_LEVEL`**, **`CONFEXT_SCOPE`** (default accepted scope `system portable`), matched against host `ID`/`ID_LIKE`/`VERSION_ID`. Hierarchy override env is `SYSTEMD_CONFEXT_HIERARCHIES` (default `/etc`). Forbidden content check refuses `/usr/lib/os-release` inside the extension. | [`extension-util.c` L24–25, L37–54, L77, L147–155, L169–177](~/archive/systemd/systemd/src/shared/extension-util.c) |
| 4 | Merged `/etc` is read-only (`nosuid`) — stated as an unconditional tension | Default is read-only (`MS_RDONLY\|MS_NODEV\|MS_NOSUID\|MS_NOEXEC` for confext, `sysext.c` L185), **but v261 ships mutability**: `--mutable=no\|yes\|auto\|ephemeral\|ephemeral-import`, `[ConfExt] Mutable=`/`ImagePolicy=` in `systemd/confext.conf` + drop-ins, backed by `/var/lib/extensions.mutable` upperdirs. The §6.2 tension is real at defaults but has an official, bounded escape hatch. | [`sysext.c` L121, L127, L258–282, L975–1000](~/archive/systemd/systemd/src/sysext/sysext.c); `systemd-sysext.xml` L78, L271–286 |
| 5 | "confext has never been used here"; ticket "two years old" | Absent `/var/lib/confexts` etc. on inspection date only proves nothing is installed **in the default paths right now**; it cannot establish "never used". The beads ticket `compfuzor-systemd-extensions` was created **2026-02-16** — roughly seven months ago, not two years. | Local inspection limit; `bd show compfuzor-systemd-extensions` |

Also corrected (frame, not fact): §2 of the predecessor called its impasse
characterization "slightly unfair". That was the wrong instinct. The operator
explicitly distinguishes the **SteamOS success** (bind mounts; done) from the
**unresolved single-tree problem**, and
[`runtime0.sm.md`](/design/confext/runtime0.sm.md) §"Origins" states the same
reading independently. And to be equally precise in the other direction:
**confext is not automatically the answer to general tree portability** — it is
a candidate mechanism for one specific projection (declared, read-mostly `/etc`
material), and this doc treats it as exactly that.

## 2. What the iface playbooks actually generate — the byte trace

Ground truth: the live deployment
`/etc/opt/systemd-iface-extra-addr-eno1` (read-only inspection, 2026-09-26)
plus the two playbooks at `34518b88`-era tip (extra-addr hardened today in
`03a41dcf`, static-only created in `f00b2267`).

### 2.1 Bytes: ETC_FILES → DIR (the confext payload, for free)

For an `.etc.pb` playbook, `DIR = /etc/opt/<NAME>`
([`vars/types/etc.yaml`](/vars/types/etc.yaml)) and the ETC family root
collapses onto DIR itself — the deployed tree shows the structural link as a
self-symlink, `etc -> /etc/opt/systemd-iface-extra-addr-eno1`, with the
rendered file beside it:

```
/etc/opt/systemd-iface-extra-addr-eno1/
├── etc -> .                      # structural self-link (etc type)
├── extra-addr.conf               # rendered ETC_FILES record, 118 bytes, 0660
├── links.json                    # compiled link plan (v2)
├── bin/{apply.sh,links.mjs,install-link-records.sh,compfuzor-runtime.mjs,…}
├── compfuzor-runtime/{catalog.json,workflows/}
├── env, env.export, README.md
```

Rendered bytes (live):

```ini
# static secondary address (systemd-iface-extra-addr-eno1); DHCP stays authoritative
[Network]
Address=192.168.1.8/22
```

Mode: rendered at `FILEMODE 0660` ([`vars/common.yaml` L114](/vars/common.yaml#L113-L114));
per-file `mode` is honored by the rich writer
([`fs_hierarchy.tasks` L148](/tasks/compfuzor/fs_hierarchy.tasks#L148):
`item.mode | def(_vals.prop.mode, FILEMODE)`), and family/prop overrides
exist (L59, L90). static-only renders `iface-static-only.network` the same
way ([`systemd-iface-static-only.etc.pb` L53–69](/systemd-iface-static-only.etc.pb#L53-L69)).

**Consequence: the payload a confext needs is already fully materialized in
DIR before any host publication happens.** No new rendering machinery is
required to obtain bytes.

### 2.2 Destinations: LINKS → links.json → runtime delivery

Authored LINKS compile into `_LINK_PLAN`
([`gen_links.tasks` L1–26](/tasks/compfuzor/gen_links.tasks#L1-L26)), whose
records carry `id/origin/scope/src/dest/runtimeRoots/policy/state/strategies`
([`artifact_links.py` L322–334](/library/filter_plugins/artifact_links.py#L322-L334))
and get written to `DIR/links.json` ([`link_plan.tasks` L12–18](/tasks/compfuzor/link_plan.tasks#L12-L18)).
The live plan (v2):

```json
{ "dest": "/etc/systemd/network/en.network.d/systemd-iface-extra-addr-eno1.conf",
  "src": "/etc/opt/systemd-iface-extra-addr-eno1/extra-addr.conf",
  "policy": "replace", "state": "present", "scope": "system",
  "strategies": { "available": ["copy"], "default": "copy" } }
```

Delivery is **runtime-side**, not Ansible: `bin/links.mjs apply` (contributed
by `gen_links.tasks` L63–101 as `install-link-records.sh`) performs
symlink-or-copy through
[`files/links/delivery.ts`](/files/links/delivery.ts#L143,L163-L164) — copy is
`copyFile(source, temporary)` then `chmod(temporary, sourceStat.mode & 0o777)`
(i.e. **the copy inherits the rendered source's mode**), with sudo executors
using `cp` + `chmod <octal>`
([`operations.ts` L68–73](/files/links/operations.ts#L68-L73)) and strategy
selection `options.strategy ?? record.strategies.default`
([L229–235](/files/links/operations.ts#L229-L235)). The plan itself carries no
mode field — mode rides the source file.

After delivery, `apply.sh` normalizes the host side:
`sudo install -d -m 0755 <dir>` and `sudo chmod 0644 "$DROPIN"`
([`systemd-iface-extra-addr.etc.pb` L156–157](/systemd-iface-extra-addr.etc.pb#L156-L157)),
then `networkctl reload && reconfigure` with a DHCP-route wait — that is
**activation**, and a build-only confext step must not do any of it. (Note the
live drop-in on this host is `0644 root:root` from the Sep 22 generation;
today's delivery code would land `0660` from the 0660 source and rely on
apply.sh's normalization — a mode-policy question the builder must own, §5 R4.)

### 2.3 Discovery inputs (extra-addr) — and why buildable ≠ impossible

extra-addr's governing-file discovery is three pre-compile tasks
([L183–229](/systemd-iface-extra-addr.etc.pb#L183-L229)): run
`networkctl status {{INSTANCE}}` (read-only, `failed_when: false`), parse the
`Network File:` line, and **adopt it into `NETWORK_FILE` only when the var is
empty** (L214–216); `DHCP_REQUIRED` guard at L219 with an explicit
`-e DHCP_REQUIRED=False` override. The discovery is therefore an
*overridable default*, not an essential runtime behavior: a builder invoked
with explicit inputs — `-e INSTANCE=enp3s0 -e ADDRESS_CIDR=… -e
NETWORK_FILE=en` (and `DHCP_REQUIRED=False` when the build host has no such
interface) — renders deterministically **without any live networkctl
knowledge**. The playbook itself documents the force path: "Force a basename
with `-e NETWORK_FILE=<base>` when discovery must not win" (L28–29). The
residual wrinkle is that the `networkctl status` task still *runs*; it
tolerates absence (`failed_when: false`), but a strict build-only lane may
want it skipped — a one-line `when:` guard, not a redesign.

static-only has no discovery at all — its destination is fully declared
(`/etc/systemd/network/10-{{IFACE}}-static-only.network`,
[`systemd-iface-static-only.etc.pb` L70–77](/systemd-iface-static-only.etc.pb#L70-L77))
— which is why it is the cleaner first target
([`archaeology0.fx.md`](/design/confext/archaeology0.fx.md) reached the same
ordering; the reasoning here is now byte-level, not just tension-level).

### 2.4 Rendering WITHOUT publishing host network files

Existing, already-committed switches give a render-only mode today:

| Switch | Layer | Effect on iface playbooks | Evidence |
|---|---|---|---|
| `BINS_RUN_BYPASS=True` | Ansible apply | `bins_run` lane skipped: `apply.sh` and `install-link-records.sh` never auto-run (no reload/reconfigure/chmod, no host copy) — while `links.json` is still compiled and written. | [`compfuzor.includes` L240](/tasks/compfuzor.includes#L240) |
| `COMPFUZOR_LINK_BYPASS=1` | runtime env | `links.mjs apply` exits 0 — plan exists, delivery skipped. | [`runtime/compfuzor-runtime.mjs` L3037](/runtime/compfuzor-runtime.mjs#L3037); [`files/_helpers/guard`](/files/_helpers/guard) (`COMPFUZOR_<CONCERN>_BYPASS`) |
| `LINKS_BYPASS=True` | Ansible compile | `gen_links` skipped: no plan, **no `links.json`**, no `install-link-records.sh`, no delivery. ETC_FILES still materialize into DIR — payload only. | [`compfuzor.includes` L117–120](/tasks/compfuzor.includes#L117-L120) |
| `DIR_BYPASS=True` | Ansible compile | **do not use** for this purpose — skips materialization entirely, so the bytes a builder needs never land. | [`compfuzor.includes` L166–170](/tasks/compfuzor.includes#L166-L170) |

So `ansible-playbook -i 'localhost,' -c local systemd-iface-static-only.etc.pb
-e INSTANCE=ens3 -e … -e BINS_RUN_BYPASS=True` is the render recipe: **link
compilation stays on** (gen_links runs, `_LINK_PLAN` compiles,
`DIR/links.json` is written), while the bins_run lane is skipped — so
`install-link-records.sh` and `apply.sh` are materialized into `DIR/bin` but
never executed, and nothing is copied into host `/etc/systemd/network`.
`LINKS_BYPASS=True` is the *payload-only variant*: it skips gen_links
entirely, so the tree has no `links.json` and destination knowledge must come
from elsewhere (inventory or builder declaration); it is not the recipe for
the R1 input contract below.

Scope of that claim — inspected, not render-tested. From source, with
`BINS_RUN_BYPASS=True` on these two playbooks: the direct playbook tasks that
still run are read-only (`networkctl status` guards, extra-addr L183–186,
static-only L181–193; both tolerate a foreign build host — static-only's
assert passes benignly when the interface is absent, extra-addr needs its
`-e NETWORK_FILE=`/`-e DHCP_REQUIRED=False` overrides per §2.3); the ETC
family structural link self-skips for etc-type (roots equal,
[`compfuzor.includes` L171–174](/tasks/compfuzor.includes#L171-L174)); bins
materialization and `bins_link` write only inside `DIR`; the global-bins lane
is var-gated off (`GLOBAL_BINS` unset → [`bins_link_global` skip,
L272–274](/tasks/compfuzor.includes#L272-L274)); the systemd lane's legacy
import is commented out and `systemd.thunk` needs `SYSTEMD_SERVICE` (absent);
all EXTRAS/REPO lanes are var-gated off. This is a read of the lane map and
these playbooks' vars — **not a tested render**, and not a general
side-effect-free mode: a playbook setting `GLOBAL_BINS`, `SYSTEMD_SERVICE`,
`REPO`, or package vars mutates other host paths and needs its own bypass
audit ([`AGENTS.md`](/AGENTS.md) bypass table), the same boundary
[`runtime0.sm.md`](/design/confext/runtime0.sm.md) draws against calling
anything here a sandbox. No deployment was run for this document.

## 3. Does the runtime catalog carry bytes/destinations? No — references only

The operator asked specifically. Verified in
[`library/filter_plugins/runtime_catalog.py`](/library/filter_plugins/runtime_catalog.py#L133-L147):

- `_resource_records(etc_files, links_plan, subsystems)` iterates `ETC_FILES`
  **only to collect names** into a set (`names.add(name)`, L136–140), then emits
  fixed contract references: `{"id": "config", "contract": "compfuzor.config/v2",
  "path": "etc/config.spec.json"}`, `{"id": "zim", …}` when `zim.spec.json` is
  among names, and `{"id": "links", "contract": "compfuzor.links/v2", "path":
  "links.json"}` when a plan exists (L142–146).
- Commands/actions record handler *paths* (`bin/<name>`) and provenance fields
  (L233–247). Nothing captures file bytes, modes, or destination mappings.

This independently confirms
[`runtime0.sm.md`](/design/confext/runtime0.sm.md) §"Verified capabilities":
"Existing resources are references to domain specs, not captured file bytes,
modes, symlinks…". **The real machine-readable build manifest already exists
and it is `DIR/links.json`** (v2, src/dest/policy/strategies/contributors,
§2.2) — plus the ETC family files themselves. A `build-confext` should
consume `links.json` + DIR material; it should **not** grow the catalog into a
byte manifest (that would conflate the catalog's observational role with
build authority — the exact boundary `runtime0.sm.md` warns to keep).

## 4. Output forms compared — confext-specific requirements (verified, not analogized)

All three forms are legitimate confexts upstream; the class is decided by
**where the image lives and what it carries**, not by a special partition GUID
(checked: `src/shared/gpt.h`/`sd-gpt.h` in v261-1244 define no
`*-extended` types — this corrects the predecessor's §5 hedge about
"partition-type GUID unresolved"; both mkosi and systemd's own repart
definitions build confext DDIs as `Type=root`).

| Form | Payload layout | Placement / discovery | Build cost & fit |
|---|---|---|---|
| **Directory** | tree whose `etc/` contains payload + `etc/extension-release.d/extension-release.<NAME>` | `/var/lib/confexts` (main), `/run/confexts` (symlinks), `/usr/local/lib/confexts`, `/usr/lib/confexts` ([`discover-image.c` L82–85](~/archive/systemd/systemd/src/shared/discover-image.c)) | `cp -a` + one metadata file; no root, no mkfs tools; instant re-build and `diff -r` iteration (the same argument that favored mkosi `directory` format in `ses_054f118f`) |
| **Naked filesystem image** (erofs/squashfs/ext4, no partition table) | same tree as the image root | same dirs; class also signaled by `.confext` suffix for raw files; metadata probing tries *both* release locations ([`discover-image.c` L2274–2278](~/archive/systemd/systemd/src/shared/discover-image.c)) | one `mkfs.erofs` invocation; compact, mountable read-only; needs the mkfs tool on the build host |
| **DDI** (GPT) | partition table built by systemd-repart | same dirs | Definitions are the authoritative recipe — mkosi v27 `confext-unsigned.repart.d`: `Type=root, Format=erofs, CopyFiles=/etc/, Minimize=best`; signed variant adds `root-verity` + `root-verity-sig`; systemd's own `src/repart/definitions/confext.repart.d/10-root.conf` adds `Verity=data` inline. Verity/signing is the reason to reach for DDIs — not needed for a first builder |

Metadata requirements are identical across forms and are small:
`etc/extension-release.d/extension-release.<NAME>` with
`ID=` (mkosi defaults to the base `ID`, else `_any`), optional
`ID_LIKE`/`VERSION_ID`/`CONFEXT_LEVEL`, `CONFEXT_ID`/`CONFEXT_VERSION_ID`,
`CONFEXT_SCOPE` (mkosi default `initrd system portable`
— [`mkosi/__init__.py` L434–470](~/archive/systemd/mkosi/mkosi/__init__.py));
and the forbidden-content rule (no `/usr/lib/os-release` in the tree).

## 5. Bounded recommendations and unresolved choices (build only)

**Recommendations**

- **R1 — input contract**: `build-confext` consumes an already-rendered
  deployment: `DIR` (payload files) + `DIR/links.json` (declared destinations)
  produced by a render-only play that **keeps link compilation on and skips
  only the bins-run lane** (`-e BINS_RUN_BYPASS=True`, §2.4). It reads; it
  never publishes. (A `LINKS_BYPASS=True` render yields the payload without
  `links.json`; a builder could accept that shape with destinations supplied
  out-of-band, but it is not this contract.)
- **R2 — output**: building the confext artifact itself is the main ask, and
  the **output-form choice — directory vs filesystem image vs DDI — is an
  in-scope user/design choice** (§4 compares the three with verified
  requirements), not something deferred. Directory form is the useful
  *intermediate and build representation* (diffable, no mkfs tools) and the
  projection from it to image/DDI is mechanical
  (`mksquashfs`/`mkfs.erofs`/repart definitions with the §4 metadata), but the
  builder should treat "which artifact does the build emit" as a declared
  option. What stays out of scope is only **installation and activation**:
  placing into `/var/lib/confexts` and running
  `systemd-confext merge/refresh`.
- **R3 — pilot targets in order**: `systemd-iface-static-only.etc.pb` first
  (fully declared destination); `systemd-iface-extra-addr.etc.pb` second with
  explicit `-e NETWORK_FILE=` (and the §2.3 note about tolerating the
  discovery task). Both destinations live under `/etc/systemd/network/` but
  with **different shapes**: extra-addr delivers a per-interface **drop-in**
  (`…/<NETWORK_FILE>.network.d/<NAME>.conf`); static-only delivers a
  **standalone `.network` file** (`/etc/systemd/network/10-<INSTANCE>-static-only.network`,
  [`systemd-iface-static-only.etc.pb` L70–77](/systemd-iface-static-only.etc.pb#L70-L77))
  that replaces the interface's first-match config. Both are ordinary `/etc`
  subtrees — exactly what a confext `/etc` overlay represents natively — but a
  builder must preserve the distinction: a standalone `.network` in a confext
  would win networkd's first-match race on every host it merges onto, whereas
  the drop-in only extends an existing governing file.
- **R4 — mode policy**: decide where host-visible modes come from. Options:
  declare `mode:` on the bundle-bound ETC_FILES records (supported,
  [`fs_hierarchy.tasks` L148](/tasks/compfuzor/fs_hierarchy.tasks#L148)); or
  have the builder normalize at packaging time to the modes apply.sh would
  have set (0644 files / 0755 dirs). Pick one and document; today the two
  layers disagree on re-render (§2.2 note).
- **R5 — manifest**: treat `links.json` as the mapping source of truth and
  leave `catalog.json` observational (§3). A builder-side
  provenance/manifest (bytes hash, source path, dest path, mode, contributor)
  is cheap to emit *into the bundle* and worth doing — it is not the same as
  promoting the catalog to build authority.

**Unresolved choices (deliberately not decided here)**

- ID/level matching strictness: `ID=_any` + no level (loosest, mkosi's
  fallback) vs pinned host ID + `CONFEXT_LEVEL`/`VERSION_ID` — decides which
  hosts accept the bundle. Upstream fallback behavior when the expected
  release file is missing (xattr-based, §1 row 2) is an extra compatibility
  lever the builder could set explicitly.
- Coexistence semantics: once a confext *and* the existing LINKS copy both
  provide `/etc/systemd/network/...`, the confext's overlay wins the merged
  view — the two lanes will fight on re-render unless the deployment picks
  one delivery. That is an activation-era question, but the builder's
  output-naming (drop-in basename = deployment id) should be chosen now so a
  future unmerge path is trivial.
- Whether `build-confext` ultimately lives as a generated bin in the bin-run
  lane (the [`build-mise`](/design/build-mise/draft0.gpt6sol.md) precedent,
  which this doc's input contract mirrors) or as a controller-side packaging
  filter. Nothing in the byte trace above requires the runtime; both homes
  remain open, and `runtime0.sm.md`'s caution about expanding the runtime's
  command surface applies to the second home.
- Payload subset selection: everything under DIR vs declared-only. The iface
  playbooks need only the ETC_FILES records (README/env/bins are deployment
  chrome) — the mapping rule "links.json `src` ∪ ETC family root, nothing
  else" is sufficient for the pilots but may not generalize.

## Cross-references

- [`archaeology0.fx.md`](/design/confext/archaeology0.fx.md) — predecessor;
  §5 corrected in situ by this doc (warning block added), §2 framing
  superseded by §1 above.
- [`runtime0.sm.md`](/design/confext/runtime0.sm.md) — companion wave; its
  "next coherent investigation" (trace declarations to bytes, classify
  availability before host mutation, verify upstream metadata rules) is what
  §2–§4 of this doc perform; its catalog-references claim is independently
  confirmed in §3.
- [`systemd-iface-static-only.etc.pb`](/systemd-iface-static-only.etc.pb) ·
  [`systemd-iface-extra-addr.etc.pb`](/systemd-iface-extra-addr.etc.pb) — the
  pilot targets traced in §2.
- [`design/build-mise/draft0.gpt6sol.md`](/design/build-mise/draft0.gpt6sol.md)
  — the bin-lane invocation/bypass/notice contract a builder bin would follow.
- [`tasks/compfuzor/gen_runtime_catalog.tasks`](/tasks/compfuzor/gen_runtime_catalog.tasks)
  · [`library/filter_plugins/artifact_links.py`](/library/filter_plugins/artifact_links.py)
  · [`files/links/delivery.ts`](/files/links/delivery.ts) — compile → plan →
  runtime delivery seam evidenced throughout §2–§3.
- [`vars/containered.yml`](/vars/containered.yml) — the profile-based portable
  tree; untouched by this direction (build-time projection, not install-time
  inversion).
- Upstream (local checkouts): `~/archive/systemd/systemd` `src/shared/discover-image.c`,
  `src/basic/os-util.c`, `src/shared/extension-util.c`, `src/sysext/sysext.c`,
  `src/repart/definitions/confext.repart.d/`;
  `~/archive/systemd/mkosi` `mkosi/__init__.py::configure_extension_release`,
  `mkosi/resources/repart/definitions/confext-unsigned.repart.d/`.

## Method and verification limits

Revision note (same day, post-review errata): the §2.4 render recipe and R1
were corrected — `LINKS_BYPASS=True` removes `links.json`, so the documented
recipe is now `-e BINS_RUN_BYPASS=True` with link compilation preserved, plus
an inspected-effects caveat (structural/global/systemd lanes) and an explicit
inspection-vs-tested-render boundary; R2 now treats image/DDI output choice as
in-scope build design; R3 corrects static-only's standalone `.network`
destination.

Upstream facts were read from the local checkouts named above (systemd
v261-1244, mkosi v27-12) — no web fetches; the archive-first rule was
satisfied for both tools. Live-host evidence came from read-only `ls`/`cat`
of `/etc/opt/systemd-iface-extra-addr-eno1` and `/etc/systemd/network/`; no
file was written outside the repo, no unit merged or restarted, and no
confext directory was created. Class-determination details verified down to
`image_discover(class)` scoping and argv[0] dispatch; not exhaustively
verified: every upstream version's behavior (v261/v27 are the tree of record
here), erofs/squashfs tool availability on this host, and image-policy
enforcement internals beyond the default policies quoted. One provenance
caveat kept honest: the deployed drop-in's `0644 root:root` predates today's
delivery-code mode behavior, so it evidences the *old* generation, not the
current one (§2.2).
