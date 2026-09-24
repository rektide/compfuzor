---
type: Design draft
title: apt subsystem on deb822 with freeform APT: stanzas
description: Initial design for converting the compfuzor apt sources lane from one-line .list generation via hardcoded APT_* vars to deb822 .sources rendered from freeform stanza maps, with hard legacy fallback.
status: draft
generated: { by: agent:glm53m (GLM 5.3 max via OpenCode), at: 2026-09-24 }
verified: { by: none, at: null }
stale_after: 2026-11-01
sources:
  - id: repo-state
    resource: /home/rektide/src/compfuzor
    title: compfuzor working copy (apt lane files read in full 2026-09-24)
    author: rektide
    last_modified: 2026-09-24
  - id: apt-upstream
    resource: https://manpages.debian.org/bookworm/apt/sources.list.5.en.html
    title: sources.list(5) — deb822 format, field list, Signed-By forms
    author: Debian apt maintainers
    last_modified: 2023
---

# apt deb822: freeform `APT:` stanzas (draft0)

## Stage setting

The apt subsystem is one of the oldest lanes in compfuzor and shows it. The
user's ask: convert it ("gen_apt.tasks and whatever") to the deb822 `.sources`
format, and while at it replace the very hardcoded authoring vars
(`APT_REPO`, `APT_DISTRIBUTION`, `APT_COMPONENT`, …) with a freeform mapping
in the spirit of the systemd section dicts (`SYSTEMD_UNITS` / `SYSTEMD_SERVICES`
/ `SYSTEMD_INSTALLS`): an `APT:` key with deb822 fields under it. Backwards
support is required, but explicitly **not** both at once: when `APT:` is
defined, the old repo vars are skipped entirely.

Vectors from the user, captured:

- deb822 is the destination format (modern apt's native, field-oriented
  sources format; Debian 13+ and Ubuntu 24.04+ default to it).
- The subsystem is "ancient and kind of crappy" — a rewrite of the authoring
  surface is welcome, not just an output-format swap.
- The parametric defaults ("ok parametric setting") are worth keeping as
  *defaults layered under* authored values, like systemd's
  `SYSTEMD_*_DEFAULT` maps.
- Freeform over hardcoded: new apt fields (Targets, By-Hash, PDiffs,
  Check-Valid-Until, …) should not each need a new compfuzor var.
- Hard precedence: `APT:` present → legacy repo vars ignored.

Research prompt for follow-up waves: "How does compfuzor's systemd unit
generation layer playbook section dicts over defaults and render via Jinja
(files/systemd.unit, vars_systemd_unit.tasks), and what would the equivalent
pipeline look like for deb822 apt sources stanzas with a Python normalizer
filter? Where does the current APT_* lane break (dead vars, broken
signed-by, .list hardcoding)?"

## Current state (assessment)

Two distinct lanes share the "apt" name; only the first is what this design
converts:

| Lane | Files | Phase | What it does |
|---|---|---|---|
| **sources lane** (the target) | [`vars_apt.tasks`](/tasks/compfuzor/vars_apt.tasks), [`apt.tasks`](/tasks/compfuzor/apt.tasks), [`files/_apt.list`](/files/_apt.list), [`files/_apt-pin`](/files/_apt-pin) | render-time, `become: True` | builds `APT_INSTALLS` records → get_url / template / dearmor / link into `/etc/apt/sources.list.d`, `/usr/share/keyrings`, `/etc/apt/preferences.d`; per-repo `apt-get update` |
| **packages lane** (aptlane subsystem) | [`gen_apt.tasks`](/tasks/compfuzor/gen_apt.tasks), `aptlane` in [`vars/common.yaml`](/vars/common.yaml#L871-L938), consumed by [`pkgs.tasks`](/tasks/compfuzor/pkgs.tasks) | gen phase → install-time `install.sh` packages lane | gathers `PKGS`/`PKGSET`/`PKGSETS` into `_apt_pkgs`, merges `install-apt.sh` + `status-apt.sh` BINS |

`gen_apt.tasks` itself is the *packages* lane generator. The deb822 conversion
is a sources-lane change; `gen_apt.tasks` is untouched unless Decision 1 below
chooses to absorb sources into the install-time lane.

Warts found while reading (evidence for "ancient and crappy"):

1. **One-line format only.** [`files/_apt.list`](/files/_apt.list) renders
   `deb [signed-by=… arch=…] url dist comps` lines. No `.sources` support
   anywhere.
2. **Hardcoded var-per-field.** `APT_REPO`/`APT_REPOS`, `APT_DISTRIBUTION(S)`,
   `APT_COMPONENT(S)`, `APT_ARCH(S)`, `APT_SOURCE` — a four-way
   singular/plural + default cascade in Jinja
   ([`_apt.list` L11-L40](/files/_apt.list)). Adding any apt repo option
   means touching this template.
3. **Dead vars.** `APT_TRUST` is set in 6 playbooks (`repo-debian.pb`,
   `repo-experimental.pb`, `xpra.pb`, `toolchains-secretsauce.pb`,
   `logmein.pkg.pb`, `hipchat.pb`) and consumed by *nothing*. `APT_KEY` is
   set in `chrome.repo.pb` and `vars/java-webupd8.yaml` and likewise consumed
   by nothing (only vendored `files/apt-repos/*.gpg.params` records them as
   data for humans).
4. **Broken signed-by path.** With no vendored keyring and no
   `APT_KEYRING_URL`, `_apt.list` still emits
   `signed-by=/usr/share/keyrings/<TYPE>.gpg` for a file nothing installs
   (`repo-debian.pb` hits this: `APT_TRUSTED` defaults to `debian`, no
   `files/apt-repos/debian.gpg` exists → the generated .list references a
   missing keyring; apt-get update on that repo fails).
5. **Render-time privilege required.** Sources/keyrings/pins template
   directly into `/etc` and `/usr/share` with `become: True`, unlike the
   systemd lane (generate under `DIR`, link/enable at install time).
6. **Legacy one-off includes** still used directly by 5 old playbooks:
   `apt.list.install.tasks`, `apt.srclist.install.tasks`,
   `apt.key.install.tasks`, `apt.list.update.tasks` (hipchat, mate, x2go,
   virtualbox, spotify).
7. **Per-repo update churn** ([`apt.update.tasks`](/tasks/apt.update.tasks))
   runs on every render unless `APT_BYPASS`/`APT_UPDATE_BYPASS`; the
   `-o Dir::Etc::sourcelist=…{{repo}}.list` option hardcodes the `.list`
   extension.
8. **71 playbooks** author with legacy `APT_*` vars — migration has to be
   gradual and non-breaking.

What is fine and stays: keyring acquisition (vendored
`files/apt-repos/*.gpg`, `APT_KEYRING_URL` + `APT_DEARMOR` flow,
`APT_TRUSTED` naming), the packages lane (aptlane), pin delivery into
`preferences.d`, and the bypass flag vocabulary (`APT_BYPASS`,
`APT_UPDATE_BYPASS`, `APTLANE_BYPASS`).

## Design

### 1. Authoring surface: freeform stanza maps

Model: systemd section dicts. A repo is a map whose keys are deb822 field
names; compfuzor knows a *few* fields and passes the rest through verbatim.

```yaml
# nodesource.repo.pb, converted
TYPE: nodesource
INSTANCE: 26.x
APT:
  URIs: https://deb.nodesource.com/node_{{INSTANCE}}
  Suites: nodistro          # nodesource ships one suite for all releases
  Components: main          # (this is also the default; shown for clarity)
APT_KEYRING_URL: https://deb.nodesource.com/gpgkey/nodesource.gpg.key
APT_DEARMOR: True
PKGS: [nodejs]
```

Renders to `/etc/apt/sources.list.d/nodesource-26.x.sources`:

```
Types: deb
URIs: https://deb.nodesource.com/node_26.x
Suites: nodistro
Components: main
Signed-By: /usr/share/keyrings/nodesource-26.x.gpg
```

Rules:

- **`APT`** — single stanza (map). **`APTS`** — list of stanza maps, all
  rendered into the same `<NAME>.sources` file separated by blank lines.
  `APT` is sugar for a one-element `APTS`. If both are set, `APT` is stanza 1
  followed by the `APTS` entries (deterministic; docs say pick one).
- **Values**: scalars render as `Field: value`; lists space-join (deb822
  multi-value fields: `Types`, `URIs`, `Suites`, `Components`,
  `Architectures`, `Signed-By` fingerprints). A value containing whitespace
  is an author error except `Signed-By` keyblocks (below).
- **Case normalization**: known fields are canonicalized (apt field names are
  case-insensitive; we emit apt's spellings: `Types`, `URIs`, `Suites`,
  `Components`, `Signed-By`, `Architectures`, `Trusted`). Unknown keys pass
  through as authored — this is the freeform escape hatch (`Targets`,
  `By-Hash: yes`, `PDiffs: no`, `Valid-Until-Max: …` need zero compfuzor
  code).
- **`deb-src`**: `Types: [deb, deb-src]` replaces `APT_SOURCE` and the
  `apt.srclist.install.tasks` include.
- **Flat repos**: `Suites: /` with `Components: []` (explicit empty list
  suppresses the default and omits the field).

### 2. Defaults layering (keep the parametric settings)

A defaults map lives in new `vars/apt.yaml`, merged *under* authored values,
exactly like `SYSTEMD_*_DEFAULT` in `vars/systemd.yaml`:

```yaml
# vars/apt.yaml
APT_DEFAULTS:
  Types: deb
  Components: main
  Suites: "{{ APT_DEFAULT_DISTRIBUTION }}"   # existing global default (forky)
```

Derived defaults applied when the corresponding input is absent:

| Field | Default | Notes |
|---|---|---|
| `Types` | `deb` | author `[deb, deb-src]` for source packages |
| `Suites` | `APT_DEFAULT_DISTRIBUTION` | existing behavior preserved |
| `Components` | `main` | `[]`/`false` suppresses and omits the field |
| `Signed-By` | `/usr/share/keyrings/{{ keyring }}.gpg` **only when** keyring acquisition is active (`APT_KEYRING_URL`, `APT_DEARMOR`, or vendored `files/apt-repos/<trusted>.gpg`) | no acquisition + no authored `Signed-By` → field omitted → apt falls back to system keyrings; **fixes wart 4** |
| `URIs` | none | required; render fails loudly if missing |

`APT_ARCH`/`APT_ARCHS` become plain `Architectures:` fields under the new
path (`Architectures: [amd64, arm64]`), no special-casing.

### 3. Keyrings

Acquisition stays orthogonal to stanza shape and keeps working for both
paths:

- `APT_KEYRING_URL` + `APT_DEARMOR` — fetched/dearmored at render, installed
  to `/usr/share/keyrings/<name>.gpg` (unchanged).
- Vendored `files/apt-repos/<name>.gpg` / `.gpg.params` (unchanged).
- `APT_TRUSTED` — keyring base name; under the new path it also feeds the
  derived `Signed-By` default.
- **Inline keyblocks** (new, optional): a multiline `Signed-By:` value (YAML
  block scalar) is passed through verbatim as an embedded OpenPGP keyblock.
  apt ≥ 2.4 (Debian 12+, Ubuntu 22.04+) — fine for this fleet; documented as
  the version floor. Lets a playbook carry one repo + one key with zero
  keyring files.
- Dead `APT_TRUST: False` semantics finally exist as the real deb822 field
  `Trusted: yes` (author it explicitly; it is *not* defaulted).

### 4. Pins as freeform stanzas

`apt_preferences(5)` accepts deb822 stanza records, so pins get the same
treatment in the same redesign:

```yaml
# repo-debian.pb, converted
APT:
  URIs: http://deb.debian.org/debian
  Suites: "{{ INSTANCE }}"            # forky…
  Components: [main, non-free, contrib, non-free-firmware]
APT_PIN:
  Pin: "release n={{INSTANCE}}"
  Pin-Priority: 600
```

`APT_PIN` (map) / `APT_PINS` (list of maps) render to
`/etc/apt/preferences.d/<NAME>.pref`. `Package` defaults to `*`; `Pin` and
`Pin-Priority` required; unknown keys pass through. Supersedes the
`APT_PIN`/`APT_PIN_PRIORITY`/`APT_PIN_PACKAGE` triple under the new path.

### 5. Rendering pipeline

Python filter, not Jinja archaeology — the same split as `zim_fragment.py` /
`config_compile.py` (normalize in Python, template stays thin):

- **`library/filter_plugins/apt_sources.py`** — `apt_sources` filter:
  `APTS` list + defaults → normalized stanza list; `apt_preferences` filter
  for pin maps. Handles canonicalization, list joining, empty-suppression,
  `Signed-By` derivation, `URIs` validation. Unit-tested standalone.
- **`files/_apt.sources`** — template that is essentially
  `{{ _apt_stanzas | apt_sources }}` (blank-line-separated stanzas).
- **`files/_apt.pref`** — `{{ _apt_pins | apt_preferences }}`.
- **`vars_apt.tasks`** — computes `_apt_stanzas`/`_apt_pins` from
  `APT`/`APTS`/`APT_PIN`/`APT_PINS` + `include_defaults: vars/apt.yaml`;
  selects `APT_INSTALLS` entries: `.sources` template record (ext
  `sources`) or `.pref` record instead of the legacy `.list`/`.pref` ones.
  Legacy entries are built only when the new-path vars are all undefined.
- **`apt.tasks`** — already generic over `APT_INSTALLS` (get_url / template
  / link loops); only the per-repo update extension changes
  (`{{repo}}.{{ext}}`). Pass `ext` alongside `repo` to
  [`apt.update.tasks`](/tasks/apt.update.tasks).

### 6. Precedence and backwards compatibility

Hard precedence, per the user's instruction:

- `APT`, `APTS`, `APT_PIN`, or `APT_PINS` defined (and truthy) → **new path
  only**. The legacy source-list vars are ignored for generation:
  `APT_REPO`, `APT_REPOS`, `APT_LIST_URL`, `APT_DISTRIBUTION(S)`,
  `APT_COMPONENT(S)`, `APT_ARCH(S)`, `APT_SOURCE`, legacy `APT_PIN` triple.
- Both families present → new path wins **and** the render emits a loud
  one-line warning naming the ignored vars (`warn`-style debug msg). Never
  silently merged.
- None of the new vars defined → legacy path byte-for-byte as today. The 71
  legacy playbooks are untouched and keep working.
- Keyring acquisition vars (`APT_KEYRING_URL`, `APT_DEARMOR`,
  `APT_TRUSTED`, `APT_SOURCELIST`) are shared vocabulary, honored by both
  paths.
- Gating in [`compfuzor.includes`](/tasks/compfuzor.includes#L226-L227)
  grows: `… or APT is defined or APTS is defined`.
- `APT_BYPASS` keeps its exact meaning (skip the render-time sources lane);
  `APTLANE_BYPASS` keeps guarding lane generation; `APT_UPDATE_BYPASS`
  still scopes to the update pass.
- Previously rendered `<NAME>.list` files are not pruned when a playbook
  switches to `.sources` (pruning undeclared artifacts is out of scope per
  the constitution); converted playbooks should delete their stale `.list`
  once, by hand.

### 7. Delivery: render-time now, install-time as an explicit follow-on

The initial conversion keeps the current delivery shape (render-time
`become` template/link into system dirs) so the diff stays about *format and
authoring*. But the architectural direction worth naming now: sources and
keyrings are just declared files, so they can become `ETC_FILES`-shaped
records under `DIR/etc/` delivered by the install lane (systemd-style
generate-then-link; see [Decision 1](#decision-1-where-sources-get-installed)).
The renderer's output records are designed lane-ready (name, dest dir, mode)
so this is a delivery swap, not a format rework.

## Decision points

Decision log (settled with rektide, 2026-09-24): Decision 1 **both, render-time
first** (delivery phases land as separate commits/slices); Decision 3
**support + test inline keyblocks in slice 1, pilots stay path-based**;
Decision 2 leans the recommendation (`APT`/`APTS`) with pin naming to
re-confirm at implementation if the legacy `APT_PIN` shadow bites.

### Decision 1: where sources get installed — SETTLED: (a) then (b)

- **(a) Keep render-time become lane (recommended for slice 1).** Smallest
  blast radius; no privilege-model change; matches "initial design" scope.
- **(b) Absorb into the aptlane install lane.** Render `.sources`/keyrings
  into `DIR/etc`, extend `install-apt.sh` (packages lane) with a
  pre-packages section: install sources+keyrings, then optionally
  `apt-get update` (gated by a `COMPFUZOR_APT_UPDATE_BYPASS` runtime guard),
  then install packages. One `sudo bash bin/install.sh` converges a fresh
  box end-to-end — the stated reason aptlane exists. Cost: reverses the
  deliberate "no update in the lane" stance (that stance was about churn,
  which a runtime bypass guard addresses), and adds an ordering dependency
  inside the packages lane.
- **(c) Deliver via the CONFIGS/LINKS machinery** (`doc/config/`): sources as
  consumer config with copy/link representation strategy. Most consistent
  with the newest subsystem, but apt sources are *inputs to the package
  lane itself* — making package installation depend on the config runtime
  bootstraps a cycle on fresh boxes.

Recommendation: (a) now, (b) as slice 3 if the fresh-box convergence story
matters (I believe it does, eventually). (c) rejected for the bootstrap
cycle.

**Settled:** both — render-time delivery first, lane absorption as a
separate later slice/commit. The lane absorption (b) is planned, not
hypothetical; slice 1 artifacts must stay lane-ready.

### Decision 2: naming

`APT`/`APTS` matches the user's phrasing and compfuzor's plural-list idiom
(`PKGS`, `ETC_FILES`…). Alternatives: `APT_SOURCES` (more self-describing,
longer); `APT_STANZAS`. Also `APT_PIN`/`APT_PINS` shadow today's legacy
`APT_PIN` *string* var — same name, new type, disambiguated by the
new-path-active guard. If that reads as too cute, `APT_PREFS` avoids the
shadow entirely.

### Decision 3: inline keyblocks — SETTLED: support in slice 1

Ship `Signed-By:` inline keyblock support in slice 1 (it falls out of the
renderer for free); convert pilots to path-based keyrings first.

## Migration plan (slices)

**Slice 1 — renderer + wiring, legacy untouched.**
`apt_sources.py` filter + `_apt.sources`/`_apt.pref` templates +
`vars/apt.yaml` defaults + `vars_apt.tasks`/`apt.tasks`/includes gating with
hard precedence and the ignore-warning. Unit tests in
`tests/filter_plugins/apt_sources.test.py` (normalization, defaults,
empty-suppression, multi-stanza, inline keyblock, missing-URIs failure, pin
rendering, precedence warning trigger).

**Slice 2 — pilot conversions.** Convert a spread that exercises every
feature: `nodesource.repo.pb` (URL keyring + dearmor + parametric suite),
`repo-debian.pb` (pin, system trust — verifies wart 4's fix, multi
component), `liquorix.repo.pb` (vendored keyring), `waydroid.repo.pb`
(vendored + URL), and one flat-repo case (e.g. `upplay.repo.pb` → `Suites:
/`). Render each into `.test-agent/apt-deb822/` with
`APT_UPDATE_BYPASS=True` and diff outputs by hand. Drop each converted
playbook's dead `APT_TRUST`/`APT_KEY` lines while there.

**Slice 3 — (optional, Decision 1b) lane absorption.** Sources/keyring
records move to install-time delivery inside the packages lane; update
policy + runtime bypass guard; `AGENTS.md` bypass table and a `doc/apt.md`
(or `skill/apt.md` sibling to `skill/systemd.md`) documenting the stanza
authoring surface.

**Not in scope:** converting all 71 playbooks (gradual, as touched); the 5
playbooks on legacy one-off includes (frozen as-is); `apt-cacher*` proxy
config; archlane.

## Testing

- Unit: the filter tests above, runnable like the other
  `tests/filter_plugins/*.test.py`.
- Integration (slice 1–2): an `archlane.test.py`-style probe that renders a
  scratch playbook through `vars_apt.tasks` + `apt.tasks` with
  `DIR_BYPASS`-style bypasses and asserts the generated
  `<payload>/…/*.sources` / `.pref` content and the precedence warning.
  Scratch lives under `.test-agent/apt-deb822/` with a README.
- Version floor check: assert rendered stanzas parse with the host `apt`
  (`apt-get indextargets`/`apt-get update -o Dir::Etc::sourcelist=…` dry
  run) where sudo is available; skip otherwise.

## Cross-references

- [`doc/subsys.md`](/doc/subsys.md) — aptlane/archlane packages-lane contract
  this design must not disturb; also the `gen_*` pattern the new lane-ready
  records should eventually follow.
- [`skill/systemd.md`](/skill/systemd.md) — the section-dict-over-defaults
  authoring pattern being mirrored (`SYSTEMD_UNITS`/`SERVICES`/`INSTALLS` +
  `SYSTEMD_*_DEFAULT`).
- [`tasks/compfuzor.includes`](/tasks/compfuzor.includes#L226-L227) — the
  legacy gate that grows the new-path condition.
- [`doc/config/README.md`](/doc/config/README.md) and
  [`doc/config/consumer-toolkit.md`](/doc/config/consumer-toolkit.md) — the
  copy/link delivery machinery relevant to Decision 1 (and why 1c cycles).
- [`PLAN-systemd-refactor.md`](/PLAN-systemd-refactor.md) — precedent for
  refactoring a crusty generation lane into defaults+dict authoring while
  keeping playbooks working.
- [`AGENTS.md`](/AGENTS.md) — bypass flag table (`APT_BYPASS`,
  `APT_UPDATE_BYPASS`) that slice 1 must keep accurate.
