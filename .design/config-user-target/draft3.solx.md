---
type: DesignProposal
title: Install strategy toolkits for targets, drop-ins, and global bins
description: Generalize copy/link delivery into generated strategy toolkits with one default, layered bypass controls, Zim user-directory delivery, and global-bin health status.
resource: /.design/config-user-target/draft3.solx.md
tags: [compfuzor, config, targets, bins, install, strategies, bypass, zim, xdg]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: unverified }
stale_after: 2026-12-08
sources:
  - id: prior-draft
    resource: /.design/config-user-target/draft2.solx.md
    title: Scoped targets and assemble-into-user configs
  - id: bin-globalizer
    resource: /tasks/compfuzor/bins_link_global.tasks
    title: Current global BINS symlink materializer
  - id: bin-disarm
    resource: /library/filter_plugins/bin_disarm.py
    title: Generated-bin runtime bypass resolver
  - id: config-runtime
    resource: /files/config-run.sh
    title: Config candidate, commit, and status runtime
  - id: zim-host
    resource: /zim.opt.pb
    title: Zim host config, install, and startup loaders
  - id: global-usermode
    resource: /.design/global-usermode/init0.opencode.md
    title: Runtime user path and activation principles
---

# Install strategy toolkits for targets, drop-ins, and global bins

> **Authoring model:** GPT-5.6 Sol xhigh (`solx`).

## Round-4 position

The following draft2 decisions are now locked:

- the public declaration field is `targets`;
- system-scope effects use a separate privileged executor; `config.sh` never
  escalates;
- Zim adopts Option B: `ZIM_CONFIG_FILE` is a user-owned zimrc, delivered by
  copy by default;
- pairwise `cmp` decides the `--threeway` 0/1/2/3 result; diff3 explains it;
- post-commit target failures return 4, preserve committed output, and cause
  `config-remote.ts` to keep rather than roll back its input mutation;
- claim safety, no-prune behavior, direct assembly, additive block policy, and
  runtime user-path resolution remain as specified in draft2.

The new architectural element is a **strategy toolkit with one default**. A
whole-file delivery does not compile to one irreversible strategy. It compiles
to all applicable actions—normally copy and link—plus one selected default for
ordinary install runs. Operators can invoke either action directly; playbooks
can choose defaults or suppress generation; runtime bypasses can skip a variant
without rerendering.

This pattern should be shared by:

1. config and artifact targets;
2. config-input delivery into consumer drop-in directories;
3. global executable installation from BINS and language build outputs.

Block insertion remains a fixed structural strategy rather than pretending
that replacing an aggregate startup file with a symlink is equivalent. “All
strategies” means all **semantically applicable** strategies for the surface.

## Strategy toolkit model

### Declaration

Replace draft2's singular `strategy: copy|symlink` on whole-file targets with a
normalized strategy set:

```yaml
targets:
  - id: zimrc-user
    scope: user
    file:
      env: ZIM_CONFIG_FILE
      default: "$HOME/.config/zsh/zimrc"
    strategies:
      default: copy
      available: [copy, link]
```

`available` normally need not be written. Defaults are inferred by target kind:

| Target kind | Default available set | Built-in default |
|---|---|---|
| whole-file `file` or `dir` delivery | `[copy, link]` | `copy` |
| managed block (`name`/block policy present) | `[block]` | `block` |
| invariant registry link | explicitly `[link]` | `link` |

The normalized plan always records both `available` and `default`; runtime code
does not rediscover them from destination shape. `symlink` from draft2 becomes
the public strategy token **`link`**, matching generated bin names and bypass
units. Its implementation remains a symbolic link with draft2's safety rules.

`available` is an escape hatch for semantic restrictions, not routine boilerplate.
For ordinary whole-file and drop-in delivery, omitting it intentionally exposes
both copy and link.

### Default precedence

Defaults are policy, not availability. Resolve them at compile time from most
specific to least:

1. target `strategies.default`;
2. surface playbook variable;
3. global playbook variable `INSTALL_STRATEGY_DEFAULT`;
4. built-in `copy` for whole-file delivery or `block` for blocks.

Surface variables are:

| Surface | Playbook default |
|---|---|
| config/artifact targets | `TARGETS_STRATEGY_DEFAULT` |
| config input → user drop-ins | `CONFIG_USER_DROPINS_STRATEGY_DEFAULT` |
| global bins | `BINS_STRATEGY_DEFAULT` |

The repository default for copy/link toolkits is copy. A playbook can make link
ordinary behavior without hiding copy:

```yaml
BINS_STRATEGY_DEFAULT: link
```

If generation controls remove the selected default, compilation fails. Never
silently substitute an available sibling strategy: a bypass must not turn a
requested copy into a link.

### Runtime selection

Ordinary dispatchers resolve one strategy from:

1. the directly invoked strategy variant;
2. `COMPFUZOR_<SURFACE>_STRATEGY`;
3. `COMPFUZOR_INSTALL_STRATEGY`;
4. each compiled record's default.

The concrete selectors are `COMPFUZOR_TARGETS_STRATEGY`,
`COMPFUZOR_CONFIG_USER_DROPINS_STRATEGY`, and
`COMPFUZOR_BINS_STRATEGY`.

Selectors apply to multi-strategy records. A singleton record such as a managed
block or Zim's registry link is an invariant and uses its only strategy during
an ordinary install. If a selector requests a strategy unavailable to a
non-singleton record, fail that record rather than falling back.

Examples:

```bash
# One explicit action.
/opt/zim-main/bin/install-targets-link.sh

# Select link while running the ordinary entry point.
COMPFUZOR_TARGETS_STRATEGY=link /opt/zim-main/bin/install-user.sh

# Make link the user's recurring choice by exporting the selector in that
# user's environment; the deployment's compiled default remains copy.
export COMPFUZOR_TARGETS_STRATEGY=link
```

Direct variant invocation and env selection are runtime choices; they do not
rewrite the compiled plan. A durable deployment-wide policy belongs in the
playbook default. This avoids introducing a hidden preference database in the
first implementation.

Status accepts any **available, healthy** representation as clean and reports
which strategy is present. “Default” controls what ordinary install does; it is
not a requirement that status erase a valid operator-selected link. A later
ordinary install with no override may intentionally converge back to copy.

### Safe strategy switching

Draft2's protections remain the baseline:

- copy owns regular-file content and refuses a destination symlink unless it is
  a verified sibling representation of this same target;
- link owns a symlink and refuses an existing regular file unless it is a
  verified sibling copy of this same target;
- directories and special files are always refused.

The toolkit adds one safe transition rule: one strategy may replace another
only when the live destination currently satisfies an available sibling
strategy for the same claim and source.

| Transition | Safe proof before replacement |
|---|---|
| copy → link | regular non-symlink bytes equal source |
| link → copy | symlink is non-dangling and resolves to source |
| foreign/drifted state → either | refuse; repair/inspect explicitly |

No receipt ledger is required. For an old regular file that differs, explicit
copy retains draft2's declared whole-file overwrite behavior; after it matches,
link can safely replace it. This makes switching usable without weakening first
adoption safety.

## Generated bin topology: tools exist, only the dispatcher composes

Each surface emits strategy tools plus one dispatcher:

| Surface | Ordinary dispatcher | Direct tools |
|---|---|---|
| target plan | `install-targets.sh` | `install-targets-block.sh`, `install-targets-copy.sh`, `install-targets-link.sh` |
| config user drop-ins | `install-config-user-dropins.sh` | `install-config-user-dropins-copy.sh`, `install-config-user-dropins-link.sh` |
| global bins | `install-bin.sh` | `install-bin-copy.sh`, `install-bin-link.sh` |

Emit scope-qualified user/system wrappers where required, but keep these stable
human-facing stems. The plan manager receives the scope explicitly rather than
inferring privilege from the executable's basename.

Every direct strategy tool is `compose: false`. Only the dispatcher joins the
ordinary `install.sh` or `install-user.sh` compositor. This is essential:
[`bin_composers.py:106-109`](/library/filter_plugins/bin_composers.py#L106-L109)
otherwise sees every `install-*.sh` as a child and would run copy and link in
sequence. The dispatcher:

1. invokes every singleton invariant in its sole strategy unless bypassed;
2. chooses exactly one copy/link strategy per multi-strategy delivery record using the
   precedence above;
3. groups records by selected strategy so each implementation runs once;
4. aggregates failures without falling through to another strategy.

Each direct tool applies only records that advertise its named strategy; it
does not implicitly run unrelated singleton strategies. The ordinary dispatcher
is the complete install surface. Direct tools remain useful diagnostics and
recovery operations even when a different strategy is default.

## Bypass integration at two levels

### Generation-time: do not emit the variant

Playbook variables remove capabilities before BINS and plan consumers are
generated:

| Breadth | Examples |
|---|---|
| all surfaces, one strategy | `INSTALL_LINK_BYPASS`, `INSTALL_COPY_BYPASS` |
| target surface | `TARGETS_LINK_BYPASS`, `TARGETS_COPY_BYPASS`, `TARGETS_BLOCK_BYPASS` |
| user-drop-in surface | `CONFIG_USER_DROPINS_LINK_BYPASS`, `CONFIG_USER_DROPINS_COPY_BYPASS` |
| global bins | `BINS_LINK_BYPASS`, `BINS_COPY_BYPASS` |
| whole existing mechanisms | `TARGETS_BYPASS`, `GLOBAL_BINS_BYPASS`, `BINS_BYPASS` |

For example:

```bash
ansible-playbook -i 'localhost,' -c local app.src.pb \
  -e BINS_LINK_BYPASS=True
```

must produce no `install-bin-link.sh`, no link implementation row, and no
compositor reference to that tool. This is different from merely skipping the
tool when it runs.

Per-record `strategies.available` can narrow a genuinely exceptional target.
Surface generation bypasses are preferred when the playbook wants to remove a
variant consistently.

### Runtime: generated tool exists but is skipped

Every generated strategy bin carries broad and strategy-unit guards:

| Surface | Broad runtime guard | Strategy units |
|---|---|---|
| targets | `COMPFUZOR_TARGETS_BYPASS` | `COMPFUZOR_TARGETS_{BLOCK,COPY,LINK}_BYPASS` |
| config user drop-ins | `COMPFUZOR_CONFIG_USER_DROPINS_BYPASS` | `COMPFUZOR_CONFIG_USER_DROPINS_{COPY,LINK}_BYPASS` |
| global bins | `COMPFUZOR_BINS_BYPASS` | `COMPFUZOR_BINS_{COPY,LINK}_BYPASS` |

Cross-surface `COMPFUZOR_INSTALL_{COPY,LINK}_BYPASS` may be attached as an
additional explicit guard when an operator wants to suppress one strategy
everywhere.

The generated records should use existing `bypass` entries such as
`BINS:LINK` explicitly. Automatic name-derived actions include `INSTALL` in
their token, while the requested public variable is
`COMPFUZOR_BINS_LINK_BYPASS`; explicit units guarantee that exact control.
[`bin_disarm.py:194-213`](/library/filter_plugins/bin_disarm.py#L194-L213)
already merges automatic and explicit entries, and
[`files/_helpers/guard:21-40`](/files/_helpers/guard#L21-L40) implements the
broad/unit environment checks.

If the selected/default strategy is runtime-bypassed, the dispatcher reports a
skip and does not fall back to a sibling. Fixed block work and unrelated
surfaces may continue. This preserves the compositor's body-local philosophy:
one skipped action must not suppress independent children.

## Global bins become a delivery-toolkit surface

### Current mechanism and incident

Today `global: true` is materialized directly as a symlink by
[`bins_link_global.tasks:11-22`](/tasks/compfuzor/bins_link_global.tasks#L11-L22).
It runs in the filesystem phase before normal BINS execution
([`compfuzor.includes:188-210`](/tasks/compfuzor.includes#L188-L210)). Rust has
a separate branch: `RUST_COPY=true` selects copy, while link remains the default
at [`vars/common.yaml:396-435`](/vars/common.yaml#L396-L435).

The live Jujutsu failure shows why copy should be the shared default:

```text
/usr/local/bin/jj
  -> /usr/local/src/jujutsu-git/target/release/jj
  -> missing after build cleanup
```

`/usr/local/bin/jj` still exists as a symlink, but its referent does not. The
operator receives neither a usable binary nor an installation-time error when a
later clean removes build output. The current playbook is already being amended
with `RUST_BIN: jj`; that identifies the output but does not make a linked
installation resilient.

### Compiled bin-export records

Normalize every global executable exposure into a bin delivery record:

```yaml
BINS:
  - name: tool
    global:
      scope: system
      strategies:
        default: copy
```

`global: true` remains shorthand during migration, normalized to the applicable
scope and the copy/link toolkit. Sources include:

- a rendered/wrapped BINS file under `BINS_DIR`;
- a declared build output such as `target/release/jj`;
- dynamically enumerated language outputs such as Rust `RUST_ALL`.

The compiler emits the same destination class used by draft2 targets:
`scope: system, dir: bin`, destination basename from the source. Usermode uses
the runtime user bin class. The system executor applies ordinary copy after
local bins/build outputs exist; manual `install-bin-copy.sh` and
`install-bin-link.sh` remain available.

Copy installation dereferences the build artifact into an executable regular
file, uses remove-destination safety, and ensures executable mode. A subsequent
source-tree clean cannot break the installed binary. Link remains useful for
rapid development and is an explicit operator choice.

Language-specific installers should publish bin delivery records rather than
hand-roll strategy branches. Rust's `RUST_COPY` remains a compatibility input
temporarily, translated into `BINS_STRATEGY_DEFAULT`, then deprecates. Go and
other `ln -sf` installers migrate incrementally; bespoke package-manager global
installs are not forced into a file-delivery abstraction.

### Near-term status win

The target status contract already detects exactly this incident:

```yaml
scope: system
dir: bin
strategies:
  available: [copy, link]
  default: copy
```

- copy health: destination is a regular executable with source-equal bytes;
- link health: destination is a symlink resolving to the declared source;
- a dangling `/usr/local/bin/jj` link: unhealthy link, actionable drift.

This status can land before every global-bin producer is migrated. Jujutsu is
the tracer bullet: rebuild `jj`, apply `install-bin-copy.sh`, and verify that a
later target-directory clean leaves `/usr/local/bin/jj` runnable while source
status reports the build artifact missing/stale.

## Zim Option B: copy default, link tool, user-directory framing

### Initial topology

Zim keeps `/etc/opt/zim-main/zimrc` as canonical assembled output, but runtime
Zim consumes a user-owned path:

```yaml
CONFIGS:
  zimrc:
    processor: block-in-file
    # existing inputs, validation, and block namespace ...
    targets:
      - id: zimrc-user
        scope: user
        file:
          env: ZIM_CONFIG_FILE
          default: "$HOME/.config/zsh/zimrc"
        strategies:
          default: copy
          available: [copy, link]

      # Stable host-discovery evidence, not an interchangeable content copy.
      - id: zimrc-host-registry
        scope: user
        file:
          env: ZIM_CONFIG_LINK
          default: "$HOME/.config/zsh/zimfw.conf"
        strategies:
          default: link
          available: [link]
```

Ordinary config apply copies canonical zimrc to `ZIM_CONFIG_FILE`. A user can
run `install-targets-link.sh`, set `COMPFUZOR_TARGETS_STRATEGY=link`, or set a
playbook default to link the user path instead. The `zimfw.conf` registry remains
a link to the canonical host output regardless; it is structural discovery
evidence, not the selected runtime representation.

Copy default changes the old lazy behavior. Today the startup loader points
straight at ETC, so a canonical reassembly is immediately visible. With Option
B, visibility occurs only after post-commit target delivery. This is why the
retained lifecycle matters:

1. build and validate canonical zimrc;
2. atomically commit it;
3. copy/link `ZIM_CONFIG_FILE`;
4. return exit 4 if delivery fails, retaining canonical output;
5. make `config-remote.ts` retain the contributing input on that post-commit
   result so retry can converge the user target.

The old user copy remains runnable after a failed delivery; status reports bit
2 (or bit 3 if inputs also changed). Link opt-in recovers the old immediate
visibility but knowingly accepts source-path availability risk.

### Host discovery must use the registry, not runtime ZIM_CONFIG_FILE

Contributor host discovery currently prefers `ZIM_CONFIG_FILE` and otherwise
uses `~/.config/zsh/zimfw.conf` at
[`gen_zim.tasks:141-159`](/tasks/compfuzor/gen_zim.tasks#L141-L159). Under Option
B, `ZIM_CONFIG_FILE` resolves to a regular user copy; walking upward from it
cannot identify `/opt/zim-main` and falls back by accident.

Change the discovery contract to:

1. `ZIM_HOST_DIR` explicit override;
2. `ZIM_CONFIG_LINK` or default `~/.config/zsh/zimfw.conf` registry symlink;
3. `/opt/zim-main` fallback.

Runtime Zim reads `ZIM_CONFIG_FILE`; contributor installation discovers the
host through `ZIM_CONFIG_LINK`. The two variables no longer pretend to be the
same role.

### Delivering canonical pieces into the user's directory

Annotate a config's glob input with a fan-out target template:

```yaml
CONFIGS:
  zimrc:
    inputs:
      - glob: zimrc.d/*.conf
        name: zimrc
        remote: true
        targets:
          - id: zimrc-user-dropins
            scope: user
            dir: config
            subpath: zsh/zimrc.d/compfuzor
            strategies:
              default: copy
              available: [copy, link]
```

Unlike an output target, an input-glob target is a **fan-out template**. At
runtime it expands each currently enabled canonical input to one user-directory
destination using the source basename. Copy follows the canonical input's
content; link points at the canonical input path and status resolves through any
producer symlink.

Generate a dedicated toolkit:

- `install-config-user-dropins.sh` — ordinary dispatcher, copy default;
- `install-config-user-dropins-copy.sh` — explicit copy setup/repair;
- `install-config-user-dropins-link.sh` — explicit development linkage.

All use `scope: user`, runtime XDG config resolution, the standard strategy
selectors, and `CONFIG_USER_DROPINS_{COPY,LINK}_BYPASS` generation plus
`COMPFUZOR_CONFIG_USER_DROPINS_{COPY,LINK}_BYPASS` runtime controls. The
dispatcher joins `install-user.sh`; config post-commit apply can invoke the same
surface for inputs owned by the selected config.

Only declared/current input basenames are status obligations. Extra user files
and old orphaned managed copies are not automatically removed. If these files
later become active config inputs, the direct assembler must consume the
current target-plan manifest—not blindly glob the managed subdirectory—so an
orphan cannot silently remain active. User-authored additions belong in a
separate `~/.config/zsh/zimrc.d/local/` glob.

### Attractive end state: both poles, at different layers

The two poles must not simultaneously own the same aggregate path. The staged
direction is:

1. **Initial Option B:** canonical `/etc/opt/zim-main/zimrc` is copied by default
   to `~/.config/zsh/zimrc`; user drop-ins are also delivered for tooling and a
   later migration.
2. **Future composed poles:** Pole A delivers canonical *pieces* into
   `zimrc.d/compfuzor`; Pole B directly assembles the user-owned zimrc from the
   current managed manifest plus `zimrc.d/local`, preserving unmanaged aggregate
   content and supporting additive managed blocks.
3. At that cutover, retire the aggregate copy/link target for
   `~/.config/zsh/zimrc`; otherwise post-commit copy would erase the direct
   assembler's customization. Keep the independent `zimfw.conf` registry link.

This gives “canonical source, user-owned assembly” without pretending that a
canonical whole-file copy and direct in-place assembly can safely race.

## Retained target contracts

### Comparison and status

Pairwise comparison remains unchanged:

| Candidate vs materialized | Materialized vs user | `--threeway` result |
|---|---|---:|
| equal | equal | 0 |
| different | equal | 1 |
| equal | different | 2 |
| different | different | 3 |

Operational failures return 4. Generated reporters collapse drift to canonical
0 clean / 1 drift / 2 not-applicable. Diff3 is human-facing only. ETC_FILES and
bin exports have only materialized-to-installed two-way status.

For whole-file toolkits, status identifies whether copy or link currently
represents the source and accepts either when available and healthy. Wrong inode
type, foreign links, dangling links, and source/content mismatch are drift.

### Claims and no-prune

Retain draft2's compile-time symbolic and runtime resolved claims:

- block claims `(file, block name)`;
- file-form copy/link claims the file;
- dir-form copy/link claims `directory/source-basename`, not the directory;
- whole-file and block claims conflict on one path;
- two sources cannot derive one drop-in/bin destination;
- output, evidence, source, and target destinations cannot collide.

Strategy variants share one claim; they are alternative representations, not
conflicting owners. Extra files in drop-in/bin directories and destinations
whose declarations disappear remain out of scope for automatic prune.

### Install transaction and privilege

Config apply still validates all candidates and atomically commits outputs
before immediate user target delivery. It applies selected targets even when an
output was unchanged, attempts all independent work, and returns 4 after any
post-commit failure without rolling back output or successful targets.

User effects run as the invoking user with runtime HOME/XDG resolution. System
effects run in the separately generated privileged lane; config.sh never sudoes.
The target manager derives its deployment root from its own script path rather
than trusting an ambient foreign `DIR`.

## Dir-class roots: consumer paths and staging paths can coexist

Draft2's class table is a **consumer-facing** contract: it answers “where does
the external application search?” User `config`, `state`, `log`, and `share`
therefore use XDG-standard runtime roots:

- config → `${XDG_CONFIG_HOME:-$HOME/.config}`;
- state → `${XDG_STATE_HOME:-$HOME/.local/state}`;
- log → `${XDG_STATE_HOME:-$HOME/.local/state}/log` (pending confirmation);
- share → `${XDG_DATA_HOME:-$HOME/.local/share}`.

The existing USERMODE family is an internal deployment/staging hierarchy. In
the current source at [`vars/common.yaml:51-64`](/vars/common.yaml#L51-L64), it
uses `~/.local/var/lib` for VARS, `~/.local/var/log` for LOGS, and
`~/.local/usr/share` for SHARES. Those paths keep a Compfuzor deployment's FHS
shape together; they need not dictate where an XDG-aware consumer reads config
or state. Watchman already demonstrates an external consumer path using
`${XDG_STATE_HOME}` at [`vars/common.yaml:36-45`](/vars/common.yaml#L36-L45).

The two models can stand without a repository-wide “fix”: staging classes and
consumer target classes answer different questions. The compiler should name
that distinction rather than overloading one lookup mode.

The reported `USERMODE_CACHE_DIR: "{{XDG_CACHE_HOME}}/.cache"` oddity was a
valid historical issue—it could double-suffix or become `/.cache` when unset—but
the current checkout has already corrected line 53 to
`USERMODE_CACHE_DIR: "{{HOMEDIR}}/.cache"`. It is no longer an outstanding
change here. `USERMODE_CACHES_DIR` independently has the same correct root.

The still-open root choices are the consumer-facing user-log convention and
whether system `share` should follow existing `SHARES_DIR=/usr/share` or locally
managed `/usr/local/share`.

## Evidence sidecars: the ambiguity they solve

For a canonical deploy-down config, the materialized output is naturally slot
2. For direct assemble-into-user without evidence, materialized and user are the
same file. Suppose a managed block differs from today's candidate. Two causes
are observationally identical:

1. declared inputs changed since the last successful apply;
2. the user edited the managed block after the last successful apply.

Both appear only as `candidate != current user block`. With no independent
middle snapshot, status cannot truthfully decide whether the source-change bit
or user-edit bit deserves attribution; co-resident slots merely collapse the
diagnostic to “rerun direct assembly.”

An opt-in evidence sidecar stores the last successfully applied managed-block
projection, excluding unmanaged user text:

```text
slot 1: current candidate managed blocks
slot 2: last-applied evidence sidecar
slot 3: current user managed blocks
```

It restores attribution:

- slot 1 ≠ slot 2: inputs changed since apply;
- slot 2 ≠ slot 3: user edited managed content;
- both: mixed drift.

Evidence costs another durable file, another output in the commit transaction,
and a policy for missing/stale sidecars. It does not own unmanaged content and
must never become the source copied over the user's whole file. Whether every
direct config should emit it remains open; the design supports both modes.

## Ordered implementation commits

1. **Strategy-set schema.** Replace singular whole-file strategy with normalized
   `{available, default}`, layered defaults, fixed block/link-only records, and
   compile errors when suppression removes a default.
2. **Strategy dispatcher generator.** Emit non-composed block/copy/link tools
   and one composed dispatcher per surface/scope; test that ordinary install
   executes exactly one copy/link choice.
3. **Generation bypass controls.** Add global/surface strategy bypass variables,
   prune unavailable variant bins and plan implementations, and verify extra-var
   suppression leaves no compositor reference.
4. **Runtime bypass and selection.** Attach exact broad/unit disarm entries,
   add global/surface selectors, prohibit fallback after bypass, and test direct
   variants plus ordinary dispatch.
5. **Strategy-aware health and switching.** Accept any healthy available
   representation, detect actual strategy, and permit only verified sibling
   transitions while retaining draft2's foreign-file safety.
6. **Global bin export compiler.** Normalize `global: true`/mapping declarations
   and subsystem build outputs into bin target records; generate system/user
   copy/link tools and status.
7. **Global bin apply migration.** Replace direct
   `bins_link_global.tasks` symlinking with copy-default privileged application
   after local bin/build materialization. Preserve delayed/postRun semantics.
8. **Rust tracer bullet.** Translate `RUST_COPY`, publish Rust outputs through
   the bin toolkit, migrate Jujutsu, repair `/usr/local/bin/jj` as a copy, and
   test that cleaning `target/` does not break it while link status detects a
   dangling opt-in install.
9. **Target toolkit integration.** Apply strategy sets/default dispatch to the
   draft2 config/artifact target plan while retaining pairwise status, claims,
   system lane, and post-commit exit 4.
10. **Config-input fan-out.** Compile glob-input target templates, emit
    `install-config-user-dropins-{copy,link}.sh` plus dispatcher/status, and
    consume only current manifest entries.
11. **Zim Option B topology.** Set runtime `ZIM_CONFIG_FILE` to the user path,
    add copy-default/link-available aggregate delivery, retain the link-only
    `zimfw.conf` registry, and change contributor discovery to use that registry.
12. **Zim timing/rollback tests.** Exercise config-remote source changes,
    post-commit delivery failure, old-copy survivability, retry, link opt-in,
    and three-way bits.
13. **Zim drop-in setup.** Deliver canonical input fragments to the managed
    user drop-in directory with copy default and add a separate local-custom
    directory contract; do not yet make it the active assembler input unless
    the direct-pole migration is selected.
14. **Retained migrations.** Move Mise blocks and Jujutsu conf.d to target
    declarations; restore Zim's generic STATUSES orchestrator and fix its
    unbound `ZIM_CONFIG_FILE` status reference.
15. **Direct-pole infrastructure.** Land direct output/evidence/additive support
    and migrate Clickpad independently of the Zim copy-default rollout.
16. **Documentation.** Record toolkit defaults, selectors, both bypass levels,
    strategy switching, bin exports, Zim's registry/runtime split, dir-class
    duality, and evidence semantics in `doc/arch.md`.

## OPEN QUESTIONS

### Human briefing still pending

1. **Consumer dir roots:** user log at `${XDG_STATE_HOME}/log` versus the
   staging-style `~/.local/var/log`; system share at `/usr/share` versus
   `/usr/local/share`.
2. **Evidence default:** opt in per direct config, or emit a managed-projection
   sidecar for every direct config?

### New questions from strategy toolkits

3. **Runtime choice persistence:** is an exported selector/playbook default
   sufficient for recurring link users (recommended for v1), or should direct
   strategy bins write a persistent per-user/per-system preference file?
4. **Status meaning:** should any healthy available strategy be clean
   (recommended), or should status report a healthy nondefault strategy as
   drift even though the toolkit explicitly offers it?
5. **Block variants:** keep block as a fixed non-interchangeable strategy
   (recommended), or generate whole-file copy/link actions even for aggregate
   files where they would destroy unmanaged content?
6. **Zim user drop-ins activation:** generate and populate the managed drop-in
   directory now as preparation (recommended), or defer it until the future
   direct-pole assembler consumes it?

## Cross-references

- [`draft2.solx.md`](/.design/config-user-target/draft2.solx.md) defines the
  retained poles, scoped location grammar, pairwise status, strategy safety,
  claims, privilege split, and target transaction.
- [`bins_link_global.tasks`](/tasks/compfuzor/bins_link_global.tasks) is the
  symlink-only global exposure path the bin toolkit replaces.
- [`vars/common.yaml:366-466`](/vars/common.yaml#L366-L466) contains Rust's
  current link-default/`RUST_COPY` branch and is the first subsystem migration.
- [`bin_disarm.py`](/library/filter_plugins/bin_disarm.py) and
  [`files/_helpers/guard`](/files/_helpers/guard) provide the compile metadata
  and runtime guard vocabulary reused by every strategy tool.
- [`doc/subsys.md:354-442`](/doc/subsys.md#L354-L442) documents action
  composition, scope, phase lanes, and body-local child execution.
- [`jujutsu.src.pb`](/jujutsu.src.pb) plus the live dangling
  `/usr/local/bin/jj` link provide the bin-copy tracer bullet; its conf.d links
  remain the drop-in target tracer bullet.
- [`gen_zim.tasks:141-159`](/tasks/compfuzor/gen_zim.tasks#L141-L159) is the host
  discovery path that must split registry identity from runtime config choice.
- [`global-usermode/init0.opencode.md`](/.design/global-usermode/init0.opencode.md)
  supports runtime user resolution and the ban on deploy-time home baking.
