---
type: DesignProposal
title: Scoped deployment targets and assemble-into-user configs
description: Reconcile deploy-down replication with direct user-file assembly, pairwise drift attribution, drop-in destinations, and FHS/XDG-scoped target resolution.
resource: /.design/config-user-target/draft2.solx.md
tags: [compfuzor, config, filesystem, targets, usermode, xdg, diff3, block-in-file]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: unverified }
stale_after: 2026-12-07
sources:
  - id: round-brief
    resource: /.design/config-user-target/brief.glm53.md
    title: Binding D1-D4 deltas and design constellation
  - id: prior-draft
    resource: /.design/config-user-target/draft1.solx.md
    title: Install-driving target strategies and ETC_FILES extension
  - id: global-usermode
    resource: /.design/global-usermode/init0.opencode.md
    title: Global deploy and runtime user activation model
  - id: config-runtime
    resource: /files/config-run.sh
    title: Config candidate, validation, status, and commit runtime
  - id: artifact-compiler
    resource: /library/filter_plugins/artifact_links.py
    title: Filesystem artifact and deferred-link compiler
  - id: fsh-lookup
    resource: /library/lookup_plugins/fsh.py
    title: FHS-aware deploy and runtime-user path lookup
  - id: block-in-file
    resource: https://github.com/jauntywunderkind/block-in-file/blob/main/README.md
    title: Managed-block CLI capability surface
---

# Scoped deployment targets and assemble-into-user configs

> **Authoring model:** GPT-5.6 Sol xhigh (`solx`).

## Revision summary

Draft1's strategy contracts, target claim rules, post-commit installation,
partial-failure semantics, exit 4, `config-remote.ts` coordination, Mise-first
artifact migration, and Zim-before-Clickpad CONFIGS ordering remain the base.
This revision integrates four later decisions:

1. **Pairwise comparison decides; diff3 explains.** Machine attribution comes
   from candidate/materialized and materialized/user `cmp` results. Diff3 is the
   human-facing report and never the status oracle.
2. **Whole-file strategies accept a drop-in directory destination.** The target
   filename is the source basename. Both symlink and copy support it.
3. **Assemble-into-user is a first-class output pole.** A CONFIGS output may be
   the user's file itself. Managed blocks are configuration; unmanaged content
   is customization and never drift.
4. **Every location is scoped and may use a named directory class.** User paths
   remain symbolic until runtime; system effects use an explicitly privileged
   executor rather than contaminating the invoking-user runtime with sudo.

Because targets can now be `scope: system`, this draft renames the proposed
public field from `user_targets` to **`targets`** before implementation. The
combined runtime plan remains `user-targets.json` only as a working filename in
the examples below; `targets.json` is the cleaner implementation name. There is
no compatibility reason to ship a semantically false field name.

## Domain model: one location grammar, two poles

The two poles share the same scoped location descriptor but differ in the role
of that location.

### Pole A — deploy down, then activate

The config output or ETC_FILES artifact is canonical deployment content.
`targets` replicate or expose it through block, symlink, or copy:

```text
inputs -> would-run -> canonical materialized output -> target(s)
```

This is draft1's model. CONFIGS has three-way evidence; ETC_FILES has only
materialized-to-target evidence because it has no runtime would-run producer.

### Pole B — assemble into the user's file

The CONFIGS output is itself the user-owned file:

```text
canonical fragments + current user file -> candidate user file -> atomic output commit
```

`processor: block-in-file` copies the current output into its candidate, removes
and reinserts owned blocks, and preserves everything else at
[`config-processor.sh:34-58`](/files/config-processor.sh#L34-L58). Therefore:

- managed block bodies are Compfuzor's configuration;
- unmanaged text outside those blocks is user customization;
- unmanaged changes are carried into would-run and are **not drift**;
- replacement-mode edits inside managed blocks are drift;
- additive-mode extra lines inside managed blocks are permitted customization
  when applying the declared additive policy would leave the block unchanged.

This is an existing seam, not a new filesystem theory.
[`clickpad.user.pb:14-21`](/clickpad.user.pb#L14-L21) already directs a CONFIGS
output into the user's home under USERMODE. Its current `concat` processor owns
the whole file; migrating it to direct `block-in-file` assembly changes the
ownership boundary from “whole `.xinitrc`” to “named blocks within `.xinitrc`.”

### Public CONFIGS shape

Keep filename-keyed CONFIGS. Add an optional `output` location; without it,
legacy `dir + output key` resolution remains unchanged.

```yaml
CONFIGS:
  .xinitrc:
    name: clickpad
    pole: direct
    processor: block-in-file
    output:
      scope: user
      file: "$HOME/.xinitrc"
    inputs:
      - glob: .xinitrc.d/*
        dir: "$HOME"
```

`pole` is `canonical` (default, preserving current CONFIGS behavior) or
`direct`. It must be explicit for direct assembly: `scope: user` alone is not
enough, because canonical deployment content may also live in a user XDG tree.
`output` uses the common location grammar but has no replication strategy: the
processor defines how the candidate is assembled, and a direct output commit is
the installation. Version one permits `pole: direct` only with `scope: user`
and `processor: block-in-file`. A system file that must preserve unmanaged
content should use Pole A plus a `scope: system, strategy: block` target,
keeping privilege in the system-target executor.

An optional canonical managed-block evidence document restores an independent
middle slot:

```yaml
CONFIGS:
  .xinitrc:
    name: clickpad
    pole: direct
    processor: block-in-file
    output:
      scope: user
      file: "$HOME/.xinitrc"
    evidence:
      scope: user
      file: "$HOME/.config/clickpad/xinitrc.blocks"
    inputs:
      - glob: .xinitrc.d/*
        dir: "$HOME"
```

Evidence is a deterministic document containing only the config's managed
blocks, assembled against an empty baseline. It excludes the user's unmanaged
text. It is committed in the same output transaction as the direct user file.
It is optional: canonical fragments remain authoritative, and many direct
configs need only a two-pole convergence check.

### Three-way meaning at the direct pole

Status compares **managed-block projections**, never the full user file:

| Slot | With evidence | Without evidence |
|---|---|---|
| 1 would-run | candidate managed blocks | candidate managed blocks |
| 2 materialized | committed evidence blocks | current user managed blocks |
| 3 user | current user managed blocks | same current user managed blocks |

Without evidence, slots 2 and 3 intentionally co-reside. `--threeway` still
runs diff3 once per managed block with the same slot-2 and slot-3 snapshot for
human explanation. Pairwise comparison can then set only bit 1: rerun config to
update the direct output. This preserves the split code vocabulary without
inventing a separate install step.

With evidence, all three slots are independent. Each managed block is compared
separately, and result bits are ORed across block identities. Evidence drift is
real middle-slot drift, but the repair remains `config.sh NAME`: one apply
updates evidence and the direct user output together.

## D1 corrected: pairwise comparison decides, diff3 explains

### `--threeway` bit contract

For every byte-bearing target or managed block, retain all three slots as
transaction files and compute the two relationships directly:

```bash
source_drift=0
install_drift=0
cmp -s -- "$would_run" "$materialized" || source_drift=1
cmp -s -- "$materialized" "$user" || install_drift=1
result=$((source_drift | (install_drift << 1)))
```

| Candidate vs materialized | Materialized vs user | `--threeway` result | Meaning |
|---|---|---:|---|
| equal | equal | 0 | clean |
| different | equal | 1 | config/current-input drift; rerun config |
| equal | different | 2 | install/user drift; reinstall or inspect edit |
| different | different | 3 | both relationships drift |

With multiple targets or managed blocks, bitwise-OR each result. The first bit
is config drift; the second is target drift. Structural failures map naturally:
a missing materialized output sets bit 1, while a missing block/copy or wrong
target type sets bit 2. An inability to evaluate—missing tool, unreadable source,
or internal failure—returns operational exit 4 rather than a drift guess.

For direct CONFIGS without evidence, slots 2 and 3 are the same managed-block
snapshot. The second comparison is necessarily clean, so byte drift can produce
only result 1. With evidence, the ordinary pairwise table applies.

For additive blocks, first construct the post-policy slot-1 and slot-2
projections against the current block, then run these same pairwise comparisons.
No subset-specific status implementation is needed.

### Human-facing report

When pairwise comparison finds byte drift, print a numbered slot legend and run
default-format diff3 once for that target/block:

```bash
LC_ALL=C diff3 --text "$would_run" "$materialized" "$user" || {
  code=$?
  [ "$code" -eq 1 ] || exit 4
}
```

Diff3 output is explanatory only. Its section headers are not parsed, and its
ordinary result never determines clean/drift state. This preserves draft1's
design and the corrected decision at
[`brief.glm53.md:12-29`](/.design/config-user-target/brief.glm53.md#L12-L29).

### Reporter and artifact parity

Pole A `config.sh --check` computes the same internal bits, emits the same diff3
when useful, and collapses any result 1/2/3 to canonical reporter exit 1. Direct
CONFIGS uses its managed projections in the same way. Reporter exits remain 0
clean / 1 drift / 2 not-applicable.

ETC_FILES has no candidate slot. Its artifact reporter decides block/copy drift
with one materialized/user `cmp`, then prints unified diff for humans when the
files differ. Symlink status remains structural: `test -L`, `readlink`, and
canonical resolution are topology/type predicates, not byte comparisons.

## Common target and location grammar

### Target records

```yaml
targets:
  - strategy: block
    scope: user
    file:
      env: BASH_RC
      default: "$HOME/.bashrc"
    name: mise-main

  - strategy: symlink
    scope: user
    dir: config
    subpath: jj/conf.d

  - strategy: copy
    scope: system
    file: /etc/example/generated.conf
```

| Field | Required | Meaning |
|---|---:|---|
| `strategy` | target only | `block`, `symlink`, or `copy` |
| `scope` | yes | `user` or `system`; never inferred from USERMODE |
| `file` | exactly one locator | Exact destination path selector |
| `dir` | exactly one locator | Exact directory selector or named dir class |
| `subpath` | dir class only | Relative child directory below the class root |
| `name` | block only | Exact block-in-file block identity |
| `additive` | block only, optional | In-block customization policy |

At CONFIGS level, `pole: canonical|direct` defaults to `canonical`; `evidence`
is valid only for `direct`. `output` and `evidence` omit `strategy`, `name`, and `additive` but reuse
`scope + file|dir + subpath`. A config output resolved through `dir` appends the
CONFIGS output-key basename. A symlink/copy target resolved through `dir`
appends the source basename.

`file` and `dir` are mutually exclusive. `block` requires `file`: a block lives
inside an aggregate file, not in a drop-in directory. Symlink and copy support
both. Supporting `dir` for copy is worthwhile because some consumers merge
drop-ins but reject symlinks; it should not require a second grammar.

### Exact runtime selector

Both `file` and exact `dir` accept draft1's string or structured form:

```yaml
file:
  env: ZDOTDIR
  default: "$HOME"
  suffix: "/.zshrc"
```

- `env` is an optional valid variable name whose non-empty runtime value wins;
- `default` is required and absolute or HOME-rooted;
- `suffix` is literal, optional, and empty or slash-prefixed.

Compile `~`, `$HOME`, and `${HOME}` to a canonical `${HOME}` prefix. Reject
other shell expressions, NUL/newline, relative defaults, and traversal in
suffix/subpath. Runtime selects the named env value without recursive
evaluation, falls back to the canonical default, appends the suffix, and
requires an absolute result.

This runtime selector is a user-scope facility. New `scope: system` records must
resolve to an absolute compile-time path (directly or through a system dir
class) and reject `env`, HOME, and XDG interpolation. Ambient per-user variables
must not redirect a privileged system effect.

This remains the explicit second path property requested by the human. It
faithfully models `${BASH_RC:-$HOME/.bashrc}` and
`${ZDOTDIR:-$HOME}/.zshrc` without `eval`.

### Named directory classes

When `dir` is one of the known class names, the resolver chooses a scope-specific
root. Canonical names and aliases are:

| Canonical | Alias | System root | User runtime root |
|---|---|---|---|
| `config` | `etc` | `/etc` | `${XDG_CONFIG_HOME:-${HOME}/.config}` |
| `state` | `var` | `/var/lib` | `${XDG_STATE_HOME:-${HOME}/.local/state}` |
| `log` | — | `/var/log` | `${XDG_STATE_HOME:-${HOME}/.local/state}/log` |
| `cache` | — | `/var/cache` | `${XDG_CACHE_HOME:-${HOME}/.cache}` |
| `bin` | — | `/usr/local/bin` | `${HOME}/.local/bin` |
| `share` | — | `SHARES_DIR` (`/usr/share`) | `${XDG_DATA_HOME:-${HOME}/.local/share}` |

Implement this as an extension/shared projection of the existing `fsh` kind
table, not a second unrelated constants file. Compilation should turn a class
into a concrete system root or a canonical runtime user selector; the deployed
runtime should not need Ansible's lookup engine.

User roots are selectors resolved by the target runtime, not strings rendered
to the deploying user's home. This follows the working `%h`/`$HOME` split in
[`global-usermode/init0.opencode.md:14-21`](/.design/global-usermode/init0.opencode.md#L14-L21)
and the `fsh` lookup's explicit runtime placeholders at
[`fsh.py:14-31`](/library/lookup_plugins/fsh.py#L14-L31). It also aligns with
the parallel USERMODE directory-family precedent at
[`vars/common.yaml:51-64`](/vars/common.yaml#L51-L64) and the existing
XDG-facing playbooks at
[`xdg-dirs.user.pb:4-14`](/xdg-dirs.user.pb#L4-L14) rather than baking one
operator's resolved home into a global deployment.

This target-root table is deliberately consumer-facing, not identical to
Compfuzor's package staging roots. `ETCS_DIR=/etc/opt` remains where packages
materialize their own config; `dir: config, subpath: systemd/system/foo.d`
means the consumer's `/etc/systemd/system/foo.d`. Under user scope the author
uses the scope-appropriate `systemd/user/foo.d` subpath. The class resolver does
not rewrite domain-specific path components: “better to do nothing than go hard
on that” applies to magical systemd path translation too.

### Drop-in destination semantics

For a directory target:

```text
destination = resolve(dir class/selector) / subpath / basename(source)
```

The name is not overridable in version one. This makes the drop-in contract
predictable and gives symbolic/runtime claim validation a stable key.

The live first example is Jujutsu. Its hand-written installer links every
`etc/*.toml` into `$HOME/.config/jj/conf.d/` at
[`jujutsu.src.pb:18-25`](/jujutsu.src.pb#L18-L25). The declarations become:

```yaml
ETC_FILES:
  - name: watchman.toml
    targets:
      - strategy: symlink
        scope: user
        dir: config
        subpath: jj/conf.d
    content: |
      # ...
  - name: snapshot.toml
    targets:
      - strategy: symlink
        scope: user
        dir: config
        subpath: jj/conf.d
    content: |
      # ...
```

This is the inverse of Zim's remote input pattern: Jujutsu consumes links sent
out from materialized artifacts, while Zim links contributor fragments into an
assembler input directory. Both depend on a consumer-defined drop-in merge
contract.

Status checks only each declared expected link/copy. Extra files in the consumer
directory are neither drift nor prune candidates.

## Claim rules, extended

Retain draft1's symbolic compile-time pass and resolved runtime pass. The latter
is required because env selectors and XDG roots can alias only for one invocation.

- A block claims `(resolved file, block name)`.
- A file-form symlink/copy claims the resolved file.
- A dir-form symlink/copy claims the derived
  `(resolved directory, source basename)` file, not the whole directory.
- Distinct block names may share one aggregate file.
- A whole-file claim conflicts with every block claim on that file.
- Two sources may not derive the same drop-in destination.
- Direct CONFIGS output claims its whole path for commit safety, but its managed
  block identities describe status ownership inside that file.
- Evidence paths and source artifacts may not collide with any target/output
  destination.

Removing a declaration never removes the former block, link, copy, or drop-in.
The no-prune rule retained from draft1 also follows the project-wide deliberate
cleanup policy and the sysusers precedent that removing declarations does not
remove durable identities
([`gen-user/init.0.gpt56t.md:81-87`](/.design/gen-user/init.0.gpt56t.md#L81-L87)).

## Strategy contracts

The source remains implicit: config canonical output for Pole A, or an
artifact's `resolved_dest`. Each strategy preflights a readable regular source,
resolves claims, creates its parent/directory, and then applies.

### Block — replacement and additive policies

Replacement remains:

```bash
block-in-file -C true -n "$name" -i "$source" -o "$file"
```

Read/status remains `${CONFIG_BLOCK_IN_FILE:-block-in-file} --read`; markers and
`# source:` provenance are excluded, missing blocks are drift, and there is no
sed fallback.

The optional customization tier is:

```yaml
additive: true

# or one placement policy
additive: {before: BOF}
additive: {after: EOB}
additive: {after: '^user additions below$'}
```

It maps to `--additive` plus at most one `--additive-before` or
`--additive-after`. The upstream CLI rejects both placement directions together
([`additive-cli.test.ts:76-82`](https://github.com/jauntywunderkind/block-in-file/blob/main/test/additive-cli.test.ts#L76-L82)).

Additive clean status means: applying the declared required lines and placement
policy to the current block would produce the current block. Extra user lines
are allowed. Construct slot 1 and slot 2 as **post-policy projections against a
temporary copy of the current user block**, compare them pairwise to the
untouched current block in slot 3, and use diff3 only to explain drift. Thus:

- an extra user line appears in every projection and is clean;
- a newly declared required line appears only in slot 1 until config runs;
- a deleted required line is restored in slot-1/slot-2 projections and appears
  as user drift;
- no separate subset/equality implementation is needed.

At the direct pole the same policy is attached to config block assembly, not a
replica target. Extend CONFIGS `block:` with canonical `additive` settings and
apply them to each owned input unless an input-local block policy overrides.

### Symlink

Retain draft1's safety policy:

```bash
mkdir -p -- "$destination_dir"
ln -sfn -- "$source" "$destination"
```

Both `-n` and `-f` are required: `-n` prevents dereferencing a destination
symlink-to-directory, while `-f` replaces an existing wrong/dangling symlink.
Preflight refuses an existing regular file, directory, or special file. A
correct symlink is unchanged; a wrong symlink is replaced.

Status requires symlink inode type, a non-dangling target, and equal canonical
source/referent resolution. A different lexical link spelling is clean when it
resolves correctly. Orphan entries beside a dir-form link are out of scope.

### Copy

Copy receives the same file-or-dir destination forms as symlink:

```bash
mkdir -p -- "$destination_dir"
cp --remove-destination -- "$source" "$destination"
```

It owns whole-file bytes and intentionally replaces an existing regular file,
including user edits, when apply runs. It refuses an existing symlink,
directory, or special file instead of following/changing its ownership model.
Status requires a regular non-symlink destination; its two- or three-slot diff
snapshots use the same pairwise byte comparisons as the rest of the design.

### Capability boundary informed by block-in-file

The broader CLI surface is real but not all of it belongs in this declaration:

| Capability | Draft2 treatment |
|---|---|
| `-C true`, named blocks, `--read` | fixed block strategy contract |
| `--additive`, before/after | exposed as the one explicit in-block customization tier |
| `--envsubst` / exclude | deferred; it transforms source bytes and needs a declared transformation stage for every status slot |
| anchors / before / after outside block | deferred placement metadata; not needed by accepted consumers |
| marker tags / timestamps | tolerated by reader identity, not status evidence |
| `--remove-match` | retained inside block-in-file CONFIGS namespace reconciliation, not a target prune feature |
| custom comments/markers | deferred until a consumer requires a non-default body reader identity |

The source for these boundaries is the block-in-file full usage map at
[`README.md:93-131`](https://github.com/jauntywunderkind/block-in-file/blob/main/README.md#L93-L131).
Body envsubst must not be confused with structured path env selection: the
latter chooses a destination and never transforms configuration content.

## Compilation and durable plan

### CONFIGS

Retain the compiler seams from draft1:

- normalize `output`, optional `evidence`, and `targets` while constructing the
  per-config record at
  [`config_compile.py:225-233`](/library/filter_plugins/config_compile.py#L225-L233);
- keep target/evidence metadata in `config.spec.json` for candidate-aware
  `config.sh` behavior;
- retain generated `config-NAME.sh` and `status-config-NAME.sh` at
  [`config_compile.py:237-242`](/library/filter_plugins/config_compile.py#L237-L242);
- contribute diffutils whenever byte targets/direct managed projections exist.

The compiler records the declared/defaulted pole explicitly (`canonical` or
`direct`) in normalized state. Runtime code must not rediscover policy from
scope, processor, or path prefixes.

### ETC_FILES and other copy artifacts

[`compile_artifacts.tasks:2-43`](/tasks/compfuzor/compile_artifacts.tasks#L2-L43)
feeds file families into `compile_artifacts`.
[`artifact_links.py:73-108`](/library/filter_plugins/artifact_links.py#L73-L108)
already gives each record `resolved_dest`, writer, identity, and origin. Normalize
eligible `targets` there, restrict version one to concrete copy writers, and
flatten target contributions beside `copies`/`lines` at
[`artifact_links.py:144-165`](/library/filter_plugins/artifact_links.py#L144-L165).

ETC_FILES status remains two-way. The artifact compiler does not fabricate a
preview renderer.

### Combined target plan

After `_ARTIFACTS` exists, compile config and artifact contributions into one
versioned plan containing:

- stable target ID and origin;
- source path;
- strategy and strategy policy;
- scope;
- canonical file/dir selector, class, and subpath;
- symbolic claim key and runtime roots.

Import this generator after `compile_artifacts.tasks` and before status/bin
synthesis. Persist the plan directly as `DIR/targets.json`, analogous to
`DIR/links.json` at
[`link_plan.tasks:13-23`](/tasks/compfuzor/link_plan.tasks#L13-L23); a late
ETC_FILES contribution would miss the already-frozen artifact plan.

## Scope, environment trust, and privilege

### User scope

User effects run as the invoking process's effective user. They use runtime
`HOME`, XDG variables, and only env variables explicitly named by structured
selectors. They never sudo, infer an account from ownership, or bake the
deploying account into a global plan.

This is the proven global-deploy/user-activate pattern: static global artifacts,
`scope: user` install bins, and runtime `%h`/`$HOME` expansion
([`global-usermode/init0.opencode.md:24-36`](/.design/global-usermode/init0.opencode.md#L24-L36)).

The runtime must also distrust ambient `DIR`. The brief records a foreign
exported `DIR` causing a generated status bin to source another deployment's
`env.export` and fail under `set -u`
([`brief.glm53.md:96-101`](/.design/config-user-target/brief.glm53.md#L96-L101)).
The target manager should derive deployment root from its own resolved script
path, load that deployment's plan/env, and allow only an explicit test override.
`HOME`, XDG variables, and descriptor-named variables remain intentional inputs;
ambient `DIR` does not.

### System scope

Do not make the user target runtime opportunistically sudo. Split execution by
scope while retaining one plan and one strategy implementation:

- `scope: user` targets run in config's post-commit user phase or generated
  `install-user-targets.sh`;
- `scope: system` targets run from a generated system install leaf and an
  Ansible post-config apply task using the existing `become_calc`/become
  machinery;
- status reads the same plan without mutation and reports permission failures
  clearly.

For playbook execution, apply system targets only after filesystem artifacts and
`bins_run.tasks` have materialized/committed all sources. For manual repair,
compose `install-system-targets.sh` into the ordinary system `install.sh` path,
where privilege is already expected. Config runtime may apply a system target
only when already running with sufficient privilege; it never escalates.

This preserves draft1's invoking-user contract and the gen-user lesson that
sudo belongs to the install/effect phase, not compilation or ordinary user
activation
([`gen-user/init.0.gpt56t.md:68-87`](/.design/gen-user/init.0.gpt56t.md#L68-L87)).

A direct assemble-into-user output is user scope only in version one. A
system-scope aggregate file uses a canonical source plus system block target,
so the privileged effect remains schedulable by Ansible.

## Install lifecycle and failure semantics

### Config apply transaction

Retain draft1's lifecycle with the direct pole added:

1. select configs by explicit name or `apply: true`;
2. resolve locations and claims; preflight tools, destination types, and
   privilege lane;
3. build and validate every candidate;
4. for direct configs, build canonical managed evidence if declared;
5. atomically commit all changed canonical outputs, direct user outputs, and
   evidence documents using the existing cross-output rollback;
6. after the complete commit, apply selected Pole A user-scope targets in
   config/target order, including unchanged canonical outputs;
7. attempt every target, aggregate failures, and leave all successfully
   committed outputs/targets in place;
8. let the later privileged lane apply system-scope targets.

The direct output commit **is** its user-file installation; it is not repeated as
a post-commit target. Before replacing it:

- create its parent directory;
- accept absent or regular non-symlink output only;
- refuse symlink, directory, and special-file destinations;
- build the candidate from a copy of the current regular file so unmanaged
  content survives;
- preserve the existing file mode on replacement; use a conservative private
  mode for a newly created user file;
- keep the temporary on the same filesystem for atomic rename.

Register every temp immediately and trap `EXIT`, `HUP`, `INT`, and `TERM`.
Interrupted config runs have leaked `.config-candidate.*` files under `/etc/opt`;
the expanded transaction must improve cleanup rather than multiply that state.

### Failure after output commit

Target application is not globally atomic. Continue after each failure so all
independent targets get a convergence attempt, then return dedicated apply exit
4 for “outputs committed, one or more immediate targets failed.” Do not roll
back outputs or successful targets; retry is idempotent and rollback would make
their source stale.

Retain draft1's required coordination with
[`config-remote.ts:50-55`](/files/config-remote.ts#L50-L55) and rollback sites
at [`config-remote.ts:96-115`](/files/config-remote.ts#L96-L115) and
[`config-remote.ts:123-148`](/files/config-remote.ts#L123-L148):

- pre-commit config failure: roll back the remote input;
- post-commit exit 4: keep the input mutation, report target failure, and let a
  later apply retry target convergence.

System-scope work deferred to the privileged lane is not an exit-4 failure; it
is scheduled continuation of the same compiled plan. Outside a playbook,
`config.sh` reports the deferred system target and `install.sh` is its repair
surface.

### Artifact targets

Generate artifact-only status plus scope-specific installers:

- `install-user-targets.sh` joins `install-user.sh` and is not `run: true`,
  preserving Mise's explicit user activation;
- `install-system-targets.sh` joins system install and may be invoked by the
  post-config Ansible apply lane;
- `status-targets.sh` checks artifact Pole A targets only, avoiding duplicate
  config status.

Removing target declarations never prunes old destinations.

## Status surfaces and result codes

### Config reporters

`config.sh --check [NAME]` uses the same per-target/per-managed-block snapshots
and pairwise bits as the diagnostic, but collapses any nonzero drift bits to
reporter exit 1. Diff3 remains its human-facing explanation:

- 0 clean;
- 1 drift or evaluation failure;
- 2 not applicable.

Missing declared blocks/targets are drift. `status-config-NAME.sh` remains the
generated wrapper and therefore gains parity automatically. The generic
STATUSES orchestrator retains its contract at
[`files/status/status.sh:10-35`](/files/status/status.sh#L10-L35).

### Explicit `--threeway NAME`

For Pole A byte targets and direct configs with evidence, use the complete
pairwise 0/1/2/3 table. For direct configs without evidence, co-resident slots
2/3 mean only clean or bit 1 can arise from bytes. Symlink topology can
contribute bit 2 independently. Operational inability returns 4.

Print slot legends before reports; do not mutate in `--threeway`, `--check`,
`--stdout`, or `--list`.

### Artifact reporter

ETC_FILES and other copy-artifact targets are two-way. Block/copy report one
unified diff; symlink reports topology. The reporter returns canonical 0/1/2 and
never advertises source-change attribution it cannot possess.

## Consumer migrations

### 1. Mise — first ETC_FILES block targets

Retain draft1's migration, now with explicit scope and canonical field name:

```yaml
ETC_FILES:
  - name: mise.bashrc
    targets:
      - strategy: block
        scope: user
        file:
          env: BASH_RC
          default: "$HOME/.bashrc"
        name: "{{ NAME }}"
    content: |
      eval "$(mise activate bash)"

  - name: mise.bash_profile
    targets:
      - strategy: block
        scope: user
        file:
          env: BASH_PROFILE
          default: "$HOME/.bash_profile"
        name: "{{ NAME }}"
    content: |
      eval "$(mise activate bash --shims)"
```

Delete hand-written `install-bash-user.sh` at
[`mise.opt.pb:57-68`](/mise.opt.pb#L57-L68). Keep Mise's authored
`install-user.sh`; the generated target leaf follows it through bin composition.
Status is explicitly materialized ETC file to managed block—two-way, never
config three-way.

### 2. Jujutsu — first drop-in directory links

Move [`jujutsu.src.pb:18-25`](/jujutsu.src.pb#L18-L25) to the two ETC_FILES
`scope: user, strategy: symlink, dir: config, subpath: jj/conf.d` annotations
shown above. Delete its hand-written loop. This proves basename derivation,
drop-in claims, and no-prune status.

### 3. Zim Option A — recommended first CONFIGS target

The human's A/B decision remains open. Recommendation A still stands:

```yaml
CONFIGS:
  zimrc:
    processor: block-in-file
    # existing declaration ...
    targets:
      - strategy: symlink
        scope: user
        file:
          env: ZIM_CONFIG_LINK
          default: "$HOME/.config/zsh/zimfw.conf"
```

This truthfully models the existing symlink at
[`zim.opt.pb:295-297`](/zim.opt.pb#L295-L297), changes no content ownership, and
is the lowest-risk first CONFIGS strategy consumer.

Option B remains the user-owned `zimrc` copy:

```yaml
targets:
  - strategy: copy
    scope: user
    file:
      env: ZIM_CONFIG_FILE
      default: "$HOME/.config/zsh/zimrc"
  - strategy: symlink
    scope: user
    file:
      env: ZIM_CONFIG_LINK
      default: "$HOME/.config/zsh/zimfw.conf"
```

It creates a true third byte copy but adds install timing, changes Zim's lazy
ETC-backed update path, and requires deliberate treatment of contributor host
discovery at
[`gen_zim.tasks:141-159`](/tasks/compfuzor/gen_zim.tasks#L141-L159). Keep it a
later migration unless the human explicitly chooses it.

Zim's startup `.zshenv`/`.zshrc` loaders are still ETC_FILES, not
`CONFIGS.zimenv/zimrc` targets.

### 4. Clickpad — first direct assemble-into-user config

Change Clickpad from whole-file concat to:

- canonical fragments under `.xinitrc.d`;
- `processor: block-in-file`;
- direct user output locator `$HOME/.xinitrc`;
- optional canonical managed evidence only if three independent slots are worth
  the extra file.

Its unmanaged `.xinitrc` text then becomes customization rather than drift. A
one-time migration must recognize the old whole-file output and avoid duplicating
its content outside the new managed blocks.

### Independent Zim status repair

Regardless of A/B, retain draft1's cleanup:

1. rename authored `status.sh` at
   [`zim.opt.pb:298-351`](/zim.opt.pb#L298-L351) to `status-zim.sh`;
2. register it in STATUSES so it no longer masks the generic orchestrator;
3. initialize a local
   `zimrc_config="${ZIM_CONFIG_FILE:-{{ETC}}/zimrc}"` before every use, fixing
   the live unbound-variable failure at
   [`zim.opt.pb:308-312`](/zim.opt.pb#L308-L312);
4. remove only checks superseded by declared targets; keep Zim init freshness.

## Ordered implementation commits

1. **Shared location/target compiler.** Implement canonical `targets`, required
   scope, strategy validation, exact selectors, env/default/suffix, dir classes,
   dir/subpath resolution, additive policy, and symbolic claim keys.
2. **Comparison/report core.** Implement and fixture-test pairwise `cmp` bit
   calculation, bit OR across targets, structural drift, operational exit 4,
   display-only diff3, and explanatory unified diff for two-way artifacts.
3. **CONFIGS grammar.** Extend `config_compile.py` with direct/canonical pole,
   output/evidence locations, targets, block additive policy, and durable spec
   records while preserving processor/remotes/toggles/status bins.
4. **Artifact seam.** Normalize targets on concrete copy artifacts, flatten
   contributions from `_ARTIFACTS`, reject line/directory writers, and retain
   `resolved_dest` as source.
5. **Combined plan and claims.** Merge config/artifact records, validate symbolic
   cross-domain claims, persist `DIR/targets.json`, and generate scoped
   install/status bins plus diffutils dependency.
6. **Strategy runtime.** Implement runtime XDG/class resolution, self-derived
   deployment root, runtime collision validation, block replacement/additive
   projections, symlink topology, copy safety, and no-prune behavior.
7. **Config status runtime.** Refactor candidate lifetime, remove the
   slot-1/slot-2 early continue at
   [`config-run.sh:119-121`](/files/config-run.sh#L119-L121), retain every stream
   in transaction files, and implement `--check` plus pairwise
   `--threeway` 0/1/2/3/4 results.
8. **Direct output transaction.** Add managed-block projection/evidence,
   in-place user customization preservation, output type/mode safety, same-FS
   atomic rename, and comprehensive signal cleanup.
9. **Post-commit target apply.** Retain attempt-all aggregate-fatal semantics,
   unchanged-output repair, exit 4, and config-remote rollback coordination for
   immediate user targets.
10. **System target lane.** Add post-config Ansible application with become and
    generated manual system installer; prove that user runtime never escalates.
11. **Integration matrix.** Cover every pairwise bit combination and its diff3
    display; direct output with/without evidence; unmanaged edits; managed edits;
    additive extra/missing lines; every strategy and location form; XDG
    overrides; runtime claim aliases; wrong inode types; dangling links; partial
    target failure; remote-input post-commit failure; and temp cleanup on signals.
12. **Mise migration.** Move Bash blocks to ETC_FILES targets and remove its
    hand-written Bash install leaf.
13. **Jujutsu migration.** Move conf.d links to dir-form ETC_FILES targets and
    remove the hand-written loop.
14. **Zim status cleanup.** Restore generic STATUSES composition and fix the
    unbound config variable independently of target choice.
15. **First CONFIGS target.** Apply the human's Zim A/B decision; Option A remains
    recommended.
16. **Direct-pole consumer.** Migrate Clickpad with explicit one-time preservation
    of old whole-file content.
17. **Architecture docs.** Document poles, scope/dir classes, pairwise bits,
    system privilege lane, evidence, additive projections, and no-prune policy
    in `doc/arch.md`.

## OPEN QUESTIONS created or carried by this revision

1. **Zim A/B (carried):** choose the existing `zimfw.conf` symlink first
   (**recommended**) or immediately adopt a user-owned copied zimrc?
2. **Field rename:** now that scope includes system, accept `targets` as the
   canonical public field (**recommended**) or retain the contradictory
   `user_targets` spelling selected before D4?
3. **Directory-root table:** accept `/usr/share` from existing `SHARES_DIR` for
   system `share` and `${XDG_STATE_HOME}/log` for user `log`, or choose
   `/usr/local/share` / the existing `${HOME}/.local/var/log` convention?
4. **System scheduling:** accept the recommended Ansible/manual-install system
   lane, meaning an unprivileged standalone `config.sh` defers system targets,
   or require config apply itself to escalate (not recommended)?
5. **Direct evidence default:** keep canonical managed evidence opt-in
   (**recommended**) or emit it automatically for every direct config to ensure
   three independent slots at the cost of another durable file?

## Cross-references

- [`brief.glm53.md`](/.design/config-user-target/brief.glm53.md) is the binding
  source for D1-D4 and the live environment lessons reconciled here.
- [`draft1.solx.md`](/.design/config-user-target/draft1.solx.md) remains the
  detailed source for the retained strategy safety and post-commit transaction
  rationale and pairwise comparison model; draft2 replaces only its
  user-only-location and deploy-down-only assumptions.
- [`global-usermode/init0.opencode.md`](/.design/global-usermode/init0.opencode.md)
  supplies the runtime-user, `%h`/`${HOME}`, and conservative no-baking
  principles. Its addendum documents the existing `fsh` composition tool.
- [`gen-user/init.0.gpt56t.md`](/.design/gen-user/init.0.gpt56t.md) supports the
  explicit system-effect lane, phase ordering, and no-removal philosophy.
- [`/.design/fs-pipeline/draft0.gpt56.md`](/.design/fs-pipeline/draft0.gpt56.md)
  identifies `_ARTIFACTS` as the correct ETC_FILES normalization seam.
- [`artifact_links.py:220-279`](/library/filter_plugins/artifact_links.py#L220-L279)
  is direct precedent for scoped records, symbolic runtime roots, safety policy,
  and stable claim IDs.
- [`block-in-file README`](https://github.com/jauntywunderkind/block-in-file/blob/main/README.md#full-usage)
  grounds replacement, additive, read, envsubst, anchor, tag, and removal
  capability boundaries.
