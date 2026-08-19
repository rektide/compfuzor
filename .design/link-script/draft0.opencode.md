---
type: Design
title: Deferred scoped link installation
description: Design for compiling LINKS and file-entry link shorthand into scoped install scripts
resource: https://github.com/rektide/compfuzor/blob/main/.design/link-script/draft0.opencode.md
tags: [compfuzor, links, bins, filesystem, systemd]
status: draft
generated: { by: agent:opencode, at: 2026-08-19 }
verified: { by: unverified }
stale_after: 2026-11-19
sources:
  - id: quest
    resource: https://github.com/rektide/compfuzor/blob/main/.design/link-script/prompt0.md
    title: Deferred LINKS and per-entry link fields quest
  - id: bin-composition
    resource: https://github.com/rektide/compfuzor/blob/main/doc/bins.md
    title: Bin compositors and composers
  - id: filesystem-hierarchy
    resource: https://github.com/rektide/compfuzor/blob/main/tasks/compfuzor/fs_hierarchy.tasks
    title: Filesystem hierarchy application
  - id: current-links
    resource: https://github.com/rektide/compfuzor/blob/main/tasks/compfuzor/links.tasks
    title: Current inline link materialization
---

# Deferred scoped link installation: draft0

## Decision in brief

Treat links as compiled installation data, not as an Ansible filesystem effect.
A new link synthesis step should:

1. Convert explicit `LINKS` and link annotations on file records into one
   canonical, scoped link-spec list and render it as `etc/links.json`.
2. Validate destinations and reject conflicting ownership before rendering.
3. Generate one ordinary BINS leaf per populated scope:
   `install-links-materialize.sh` and
   `install-links-materialize-user.sh`.
4. Tag those leaves `subsystem: links`, allowing the existing bin composer to
   create `install-links.sh` / `install-links-user.sh` and attach them to
   `install.sh` / `install-user.sh`.
5. Give a generic link manager the manifest so install, status, collision
   audit, and safe removal all consume the same record.
6. Remove the direct LINKS loop from filesystem application after a migration
   window.

The generated scripts are deployed artifacts. They do not run merely because
Ansible rendered them. System links materialize when `install.sh` (or the links
leaf) runs; user links materialize when each user runs `install-user.sh` (or the
user leaf). This is the required separation between recording intent and
acting on it.

The canonical link model calls the default scope `system`, but the BINS adapter
must translate it to an omitted/empty bin scope. `bin_composers` does not treat
the string `system` specially; using it would accidentally generate
`install-system.sh` instead of the bare `install.sh`.

## Why this shape

Compfuzor already has a deferred action graph. BINS leaves carry scope and are
assembled into subsystem and top-level compositors. Building another link
runner beside that graph would duplicate ordering, bypass, reporting, and
scope behavior. Links should instead become a small generated subsystem in the
same graph.

The separate materialize leaf names are intentional. `install-links.sh` is the
reserved subsystem compositor name when `subsystem: links`; naming the leaf
that would collide with its generated parent. The resulting graph is:

```text
install.sh
`-- install-links.sh
    `-- install-links-materialize.sh

install-user.sh
`-- install-links-user.sh
    `-- install-links-materialize-user.sh
```

This preserves an addressable links-only entry point without weakening the
compositor naming contract documented in [`/doc/bins.md`](/doc/bins.md).

## Current seam

Today `vars_base.tasks` normalizes a mapping-form `LINKS` declaration to items
with `dest` and `src`. `links.tasks` later resolves relative paths, honors
`srcTemplate` / `destTemplate`, and loops those records into Ansible's
`file: state=link`. The include checks `LINKS_BYPASS`; the task checks the
older singular `LINK_BYPASS`. In contrast,
BINS are rendered first, classified by `scope`, and composed by action into
manual entry points. Scope composition is therefore available, but LINKS are
consumed too early to use it.

File records already have extension fields such as `destTemplate`; BINS have
fields including `basedir`, `scope`, `global`, and `force`. A link annotation
should follow this precedent: it enriches the artifact record, while a later
synthesis pass owns the cross-record transformation.

The required pipeline order is:

```text
normalize artifact records
        |
        v
resolve final file destinations
        |
        v
gen_links: collect + validate + emit scoped BINS
        |
        v
render links.json + generic manager/status bins
        |
        v
gen_status: compose final reporter list
        |
        v
gen_bins: generate subsystem/scope compositors
        |
        v
render files and bins
```

`gen_links` must run after the source file records have their final destination
paths, because the link source is the produced artifact, not the record's input
template. It must run before `gen_bins`, because its leaves need to participate
in compositor generation.

## Canonical link spec

Explicit declarations remain the full-fidelity interface. Normalize mapping
and list input into records with this contract:

```yaml
LINKS:
  - src: /srv/watchman-main/etc/watchman.json
    dest: '${HOME}/.config/watchman-main/watchman.json'
    scope: user
    policy: preserve
```

| Field | Meaning |
|---|---|
| `src` | Path the symlink points to. Required after normalization. |
| `dest` | Symlink path. Required after normalization. |
| `scope` | `system` or `user`; defaults to `system`. |
| `policy` | `preserve`, `fail`, or `replace`; defaults to `preserve`. |
| `relative` | Request a relative symlink payload; defaults to `false`. |
| `state` | `present` or `absent`; defaults to `present`. |
| `origin` | Compiler-added diagnostic provenance, not author syntax. |

Draft0 deliberately permits exactly one scope per link. A link has one
destination owner. Authors who need both scopes should declare two records;
this keeps collision reporting and runtime path rules unambiguous.

Compilation should also add a stable `id` derived from scope and normalized
destination. `origin` explains who declared the link; `id` lets status and
teardown refer to the same desired object across runs. Existing `force: true`
input normalizes to `policy: replace` for compatibility.

The current dict shorthand remains valid and system-scoped:

```yaml
LINKS:
  /usr/local/bin/watchman: /srv/watchman-main/bin/watchman
```

After normalization this is `dest` -> mapping key, `src` -> mapping value,
`scope: system`.

### Destination invariants

System destinations must be absolute after Ansible/Jinja rendering. User
destinations must either be absolute or begin with one of the supported runtime
roots:

- `${HOME}` for persistent user files.
- `${XDG_RUNTIME_DIR}` for runtime files.

Do not accept `~`. Tilde expansion depends on shell token position and is too
easy to accidentally quote into a literal. Do not accept `%h` or `%t` in link
scripts either; those are systemd specifiers, not shell syntax.

Runtime roots are typed data tokens with restricted placement, not arbitrary
shell. JSON rendering preserves them literally. At activation, `links.ts`
recognizes only a leading supported token, replaces it with the corresponding
process environment value, and treats the remaining suffix as opaque path
data. It must not invoke a shell or use `eval`. This preserves deferred home
expansion, including spaces and metacharacters, without turning declarative
paths into code. An unset required runtime root is an explicit source error.

## Per-entry link shorthand

`link` is sugar for producing one canonical link spec whose `src` is the
file's final output path. It does not cause a filesystem effect itself.

### Forms

```yaml
ETC_FILES:
  - name: watchman.json
    link: user

  - name: shared.conf
    link: /etc/example/shared.conf

  - name: local.conf
    link:
      dest: '${HOME}/.config/example/local.conf'
      scope: user
      policy: replace
```

The forms mean:

| Form | Expansion |
|---|---|
| `link: user` | Infer the matching user hierarchy destination and set `scope: user`. |
| `link: system` | Infer the matching system hierarchy destination and set `scope: system`. |
| `link: <path>` | Use the path as `dest`; infer scope from its runtime root, otherwise system. |
| `link: {dest, scope, ...}` | Full inline link declaration. |

The reserved strings `user` and `system` are scope shorthands. A literal
relative destination named `user` or `system` is invalid anyway because link
destinations must resolve from a known root.

### Family-to-hierarchy inference

For scope shorthand, the artifact family selects the fsh kind and the final
record basename or relative path is appended:

| Artifact family | fsh kind | User example |
|---|---|---|
| `ETC_FILES` | `etc` | `${HOME}/.config/<NAME>/<relative-name>` |
| `VAR_FILES` | `var` | `${HOME}/.local/var/lib/<NAME>/<relative-name>` |
| `BINS` | `global-bins` | `${HOME}/.local/bin/<name>` |

The exact roots come from `lookup('fsh', ...)`, not from duplicated constants
in link generation. For user-scope shell output, call fsh with
`user=True, home='${HOME}', runtime='${XDG_RUNTIME_DIR}'`. For system scope,
use the ordinary deploy hierarchy. `name=True` should be used for
application-owned ETC/VAR trees, but not for the shared user bin directory.

This gives the requested watchman expansion without per-user rendering:

```yaml
ETC_FILES:
  - name: watchman.json
    link: user
```

Conceptually compiles to:

```yaml
src: /srv/watchman-main/etc/watchman.json
dest: '${HOME}/.config/watchman-main/watchman.json'
scope: user
origin: ETC_FILES[watchman.json].link
```

The same declaration installed by Alice and Bob expands only when each runs
`/srv/watchman-main/bin/install-user.sh`.

### BINS overlap

BINS already has two unrelated link mechanisms: `link` links an external source
into `BINS_DIR`, while `global` exposes a managed bin in `GLOBAL_BINS_DIR`.
Both materialize during filesystem handling. The existing `link` meaning makes
`link: user` ambiguous; it cannot simply be reinterpreted.

Because this project is pre-1.0 and the legacy field has few in-tree consumers,
draft0 recommends a focused breaking cleanup:

1. Rename the old source-link field to `source_link` and migrate its consumers.
2. Reclaim `link` as the artifact-to-install-destination annotation shared by
   ETC_FILES, VAR_FILES, and BINS.
3. Normalize `global: true` as legacy shorthand for a generated system link.
4. Reject records combining `global`, `source_link`, and new `link` forms when
   their ownership is ambiguous.
5. Stop direct BINS link materialization after migration.

This is preferable to preserving two meanings behind shape checks forever.
`link: user` on BINS then unambiguously means expose the rendered bin at the
user `global-bins` destination during activation.

## Collection and validation

`gen_links.tasks` should build a local canonical list rather than repeatedly
mutating `LINKS` while iterating artifact families. A small filter is justified
because normalization, provenance, path inference, and conflict checks are
pure and testable outside Ansible.

Suggested interface:

```jinja
{{ LINKS | compile_links(
  etc_files=ETC_FILES,
  var_files=VAR_FILES,
  bins=BINS,
  context=link_hierarchy
) }}
```

The exact function name is not important. Its output should be inspectable as
a fact such as `_links_spec`, rendered through a generated `ETC_FILES` record
named `links.json`, and consumed to emit BINS. This follows the house pattern:
`kernel.sysctl.json` records desired state and `install-kernel-sysctl.sh`
applies it later. Keep `LINKS` as the public authoring input rather than
overwriting it with generated records; this preserves the distinction between
declaration and compiled output.

Validation must fail before scripts are rendered when:

- `src`, `dest`, or `scope` is missing or malformed.
- A scope is not `system` or `user`.
- A destination uses an expansion syntax unavailable in that scope.
- Two records claim the same normalized `(scope, dest)` with different
  sources or options.
- A file annotation cannot determine the final artifact destination.
- A source and destination are the same path.

Exact duplicate specs may deduplicate while preserving first occurrence and
origin information. Conflicting duplicates should never silently use
last-write-wins: link destination ownership is an invariant, not merge policy.

## Manifest and generic manager

`etc/links.json` is the durable boundary between compilation and activation.
It includes a schema version, deployment identity, and canonical records:

```json
{
  "version": 1,
  "deployment": "watchman-main",
  "links": [
    {
      "id": "user:${HOME}/.config/watchman-main/watchman.json",
      "src": "/srv/watchman-main/etc/watchman.json",
      "dest": "${HOME}/.config/watchman-main/watchman.json",
      "scope": "user",
      "policy": "preserve",
      "state": "present",
      "origin": "ETC_FILES[watchman.json].link"
    }
  ]
}
```

A generic `links.ts` BINS tool consumes the manifest. Generated install leaves
are thin wrappers around `links.ts apply --scope <scope>`, rather than shell
source containing one hand-rendered `ln` command per record. One data path then
supports all lifecycle operations:

| Command | Responsibility |
|---|---|
| `apply` | Materialize missing links; handle collisions according to policy. |
| `status` | Report managed, missing, overridden, and erroneous links; support JSON output. |
| `audit` | Compare multiple manifests and report duplicate destination claims. |
| `remove` | Remove only links that still point to their recorded source. |

`audit` can guarantee collision detection only across manifests it receives.
The local status integration passes the current manifest. A machine-wide audit
accepts repeated manifest paths or deployment roots; a future deployment
registry may make discovery automatic. It must not claim whole-machine
coverage without an explicit discovery mechanism.

Register a `status-links.ts` adapter in `STATUSES` whenever links exist. It
delegates to `links.ts status` and follows the existing status convention:
exit zero in sync, one for drift, and two for usage/source failure.

`links.ts remove --scope <scope>` provides whole-deployment teardown while the
manifest exists. For declaration-level retirement, normalize `LINKS_ABSENT`
into `state: absent` records. An absent record retains expected `src`; removal
is allowed only when `dest` is still a symlink to that source. This gives
migrations a safe tombstone without hidden mutable ownership state.

## Generated scripts

Emit a scope leaf only when that scope has links. Each leaf should be a normal
generated BINS record:

```yaml
name: install-links-materialize-user.sh
scope: user
subsystem: links
generated: <link operations>
```

Use the existing `_bin` wrapper for `set -euo pipefail`, environment loading,
reporting, and composability. The body delegates to the generic manager, which
creates destination parents and performs idempotent link operations.

Desired behavior per record:

1. If `dest` is already a symlink to `src`, report unchanged and continue.
2. If `dest` is absent, ensure its parent exists and create the link.
3. Under `preserve`, if `dest` is a foreign symlink or non-symlink, report an
   override and leave it untouched.
4. Under `fail`, report the collision and exit nonzero without mutation.
5. Under `replace`, atomically replace a foreign symlink or regular file.

Even `replace` must fail on directories. Directory removal is too destructive
for a convenience annotation.

### Shared don't-stomp policy

Links and ZIM_ENV should share policy vocabulary and escape-hatch grammar:

- `preserve` is the default: an existing user value or path is an override.
- `replace` is explicit declaration-level intent.
- Runtime overwrite accepts `1`, `true`, `y`, `yes`, or `*` for all records,
  or a comma-separated list of glob patterns for selected logical names.

Use `COMPFUZOR_LINKS_OVERWRITE` for links, matching the contract of
`COMPFUZOR_ENV_OVERWRITE` without overloading that env-specific variable.
Patterns match stable link ids and destinations. A future generic
`COMPFUZOR_OVERWRITE` may unify domains, but one env overwrite request must not
silently authorize filesystem replacement.

Parent creation must happen as the runtime actor. User leaves contain no sudo
and create `${HOME}` parents as that user. System leaves follow existing
install script privilege conventions; generated code should not bake in a
deploying username or home.

### Install ordering

Link activation must precede service activation. Watchman's config farm is
needed before its user service is enabled and started. Because current bin
composition preserves BINS order and has no dependency metadata, `gen_links`
should prepend its generated install leaves ahead of other install leaves,
then run `gen_bins` as the final BINS transformation.

This also exposes an existing pipeline defect: `gen_bins` currently runs before
`gen_desktop` and `gen_patches`, even though both can add BINS. Move those
producers before `gen_links`, run `gen_status` after `gen_links` has registered
its reporter, and leave exactly one final `gen_bins` pass after every BINS
producer. If install ordering later needs more than "links first," add explicit
dependency metadata rather than relying on increasingly subtle list insertion.

## Bypass semantics

The current `LINKS_BYPASS` means "do not apply links during this Ansible run."
Once link application is no longer an Ansible phase, using it to suppress
script generation would violate the core requirement to record intent.

Draft0 separates two concerns:

| Control | Meaning |
|---|---|
| `LINKS_BYPASS` | Compatibility control for any remaining legacy direct apply path only. |
| `LINK_BYPASS` | Deprecated singular Ansible alias currently checked inside `links.tasks`. |
| `COMPFUZOR_LINK_BYPASS` | Existing runtime `LINK` guard honored by generated link leaves. |
| `COMPFUZOR_LINKS_OVERWRITE` | Runtime overwrite escape hatch for selected link records. |
| `BINS_BYPASS` | Prevent rendering/running the entire BINS mechanism, as today. |

During migration, `LINKS_BYPASS=true` skips only the old Ansible link loop; it
must not remove `_links_spec` or generated BINS. After the direct loop is
deleted, mark `LINKS_BYPASS` deprecated because there is no deploy-time link
phase left. Operators invoke `COMPFUZOR_LINK_BYPASS=1 install.sh` when they
want the install graph but not its links subsystem.

The generated leaf should carry normal links subsystem bypass metadata so the
existing `_bin` guard machinery can derive the runtime variable and report a
skip. The scope and subsystem compositors stay unguarded, consistent with the
current BINS contract.

Do not set `run: true` on generated link leaves. Auto-running the user leaf
would recreate the original bug by applying it as the deploying actor. Link
materialization belongs to explicit install entry points.

## Watchman migration

Watchman's bespoke `install-user-etc.sh` is the right first consumer because
it demonstrates all important properties: globally deployed source files,
per-user destinations, runtime `${HOME}`, and more than one user activating the
same deployment.

Migration sequence:

1. Add `link: user` to each `ETC_FILES` record that belongs in the per-user
   watchman config farm.
2. Inspect the compiled `_links_spec` and generated user leaf in an integration
   test.
3. Run `install-user.sh` against two temporary HOME directories and verify
   independent symlink farms pointing to the same global sources.
4. Confirm existing regular files and foreign symlinks are reported and
   preserved as user overrides.
5. Confirm the generated links leaf runs before user service activation.
6. Confirm status and removal consume the same manifest, then delete
   `install-user-etc.sh` only after output parity is established.

This migration should not absorb watchman's state, socket, or systemd unit
paths. Those are separate consumers of fsh/systemd specifiers, not symlink
destinations.

## General health findings

### One path vocabulary, explicit expansion domains

The fsh lookup already solves hierarchy selection. Links should reuse it, but
the API should make expansion domains visible:

| Consumer | Runtime root spelling |
|---|---|
| Ansible/deploy actor | resolved absolute path |
| Shell install script | `${HOME}`, `${XDG_RUNTIME_DIR}` |
| systemd unit | `%h`, `%t` |

Converting between these spellings implicitly is unsafe. `gen_links` should
request the shell form explicitly and reject systemd specifiers.

### Destination ownership should be global

Explicit LINKS, file annotations, BINS exposure, and subsystem-contributed
links can converge on the same destination. Central compilation creates the
first place where compfuzor can detect those collisions consistently. Preserve
origin metadata through subsystem merges so diagnostics can name both owners.
The persisted manifest extends the same ownership model to runtime audit and
teardown.

### Canonicalize file destinations once

ETC_FILES and VAR_FILES do not currently retain a `resolved_dest`; destination
logic lives in task-local expressions and differs for `line:` versus copied or
generated entries. `gen_links` must not duplicate those expressions. Introduce
a shared file-record canonicalization pass and make both `fs_hierarchy.tasks`
and link compilation consume its result. This also makes `destTemplate`
behavior testable without executing filesystem tasks.

### Remove existence-dependent source resolution

Current `links.tasks` gives a relative source two meanings: it first checks
under `DIR`, then falls back to `files/<TYPE>` if that path does not exist at
deploy time. Desired data should not change interpretation based on transient
host state. Canonical compilation must resolve each source from declaration
shape and artifact provenance alone. Compatibility migration should inventory
relative explicit LINKS and rewrite ambiguous entries rather than preserving
the existence probe in the manifest manager.

### Keep hierarchy links separate

Three link systems currently coexist: top-level LINKS, hierarchy links such as
`DIR/etc -> ETC`, and BINS link/global exposure. This design absorbs top-level
LINKS and BINS exposure. It does not defer hierarchy links, which establish the
deployment's own internal layout before its manifest and scripts can be
rendered. Their `DIR_LINK_BYPASS` / `<KIND>_LINK_BYPASS` controls remain a
separate concern.

### Linking deserves the compile/apply split

Architecture docs currently classify `links_*` primarily as execution. This
design introduces two responsibilities that should be named separately:

- `gen_links`: synthesis, no host effects.
- generated install BINS: execution, host filesystem effects.

That distinction aligns links with the wider `sub_*` / `gen_*` architecture
instead of keeping normalization and execution coupled in one legacy family.

### Avoid arbitrary shell in path data

Literal `${HOME}` is useful only if the manager treats it as a recognized root
token. Passing arbitrary strings through Jinja into shell source would make
every link declaration a code-injection surface. The manifest-plus-Node design
avoids shell interpolation entirely and keeps its accepted token set
deliberately small.

### Clarify install privilege

The BINS hierarchy expresses scope but scope alone does not grant privilege.
A system-scope link into `/usr/local/bin` may still require the caller to run
the installer with sudo. Generated links should follow the existing install
contract and report permission failures plainly, not insert per-line sudo.
User-scope leaves must remain sudo-free.

## Migration and compatibility

Use a short, observable transition rather than executing both mechanisms:

1. Add canonical compilation, manifest rendering, and generated scripts while
   retaining direct apply behind an explicit compatibility flag.
2. Convert representative system and user consumers, including watchman and a
   `global: true` BINS consumer.
3. Make deferred scripts the default and disable direct apply.
4. Remove the direct loop and deprecate `LINKS_BYPASS`.
5. Remove legacy BINS `global` materialization after all declarations compile
   to links.

Do not run direct and deferred materializers by default in the same release.
Even when idempotent, dual ownership obscures which execution model is being
tested and makes bypass behavior impossible to explain.

## Verification plan

### Pure filter tests

- Dict and list normalization preserve `dest`/`src` direction.
- Scope defaults, explicit scopes, and runtime-root inference.
- ETC/VAR/BINS shorthand expansion using injected hierarchy roots.
- Final artifact destination, not input `src`, becomes link `src`.
- Exact duplicate deduplication and conflicting destination rejection.
- Unsupported `~`, `%h`, `%t`, and embedded runtime tokens are rejected.
- Manifest resolution handles spaces, quotes, shell metacharacters, and leading
  `${HOME}` safely without shell evaluation.
- Manifest ids and output ordering are deterministic.
- Legacy BINS `link` cannot be mistaken for a new install-link annotation.

### Bin composer tests

- System and user materialize leaves produce separate links subsystem
  compositors and join the correct top-level install entry points.
- A one-scope deployment emits no empty compositor for the other scope.
- Generated leaves carry links bypass metadata while compositors do not.

### Integration tests

- Syntax-check a playbook with explicit and annotated links.
- Render without changing the target link destinations.
- Run the system links leaf in a temporary root and verify idempotence,
  preserve, replacement, collision failure, and directory safety.
- Run the user installer with two temporary HOME values and verify late home
  expansion.
- Verify `COMPFUZOR_LINK_BYPASS=1` skips link operations without preventing
  sibling install subsystems.
- Verify selective overwrite follows the shared wildcard grammar.
- Verify status reports missing and overridden links in text and JSON forms.
- Verify removal deletes only links that still target their recorded sources.
- Verify audit catches duplicate destinations across supplied manifests.
- Verify links install before service activation and late BINS producers are
  included by the final composer pass.
- Verify `BINS_BYPASS` prevents script emission/application according to its
  existing contract.

## Open decisions for draft1

1. Whether explicit relative `dest` values have useful legacy semantics. This
   draft rejects them; compatibility evidence may require a defined base.
2. Whether `replace` should back up regular files rather than remove them.
3. Whether typed runtime-root resolution should become a reusable library for
   other manifest consumers after it proves out in links.
4. Whether `LINKS_ABSENT` is sufficient for declaration retirement or an
   installed-state ledger is eventually needed for automatic stale cleanup.
5. Whether the compatibility direct-apply path is worth shipping at all in a
   pre-1.0 project. A flag day is simpler if current playbooks can migrate in
   one commit.

## Cross-references

- [`/doc/bins.md`](/doc/bins.md) defines the leaf -> subsystem compositor ->
  scope compositor graph reused here.
- [`/doc/subsys.md`](/doc/subsys.md) documents BINS scope, execution order,
  generated-script fields, and subsystem artifact merging.
- [`/.design/global-usermode/init0.opencode.md`](/.design/global-usermode/init0.opencode.md)
  establishes the `%h` versus `${HOME}` expansion-domain distinction and the
  global-deploy/user-activation watchman case.
- [`/library/lookup_plugins/fsh.py`](/library/lookup_plugins/fsh.py) is the
  hierarchy and deferred-root vocabulary that link inference should reuse.
- [`/vars/common.yaml`](/vars/common.yaml) contains the kernel sysctl
  `ETC_FILES` manifest plus install/status BINS precedent reused by this design.
- [`/tasks/compfuzor/gen_status.tasks`](/tasks/compfuzor/gen_status.tasks)
  defines the reporter aggregation point that `status-links.ts` should join.
- [`/watchman.srv.pb`](/watchman.srv.pb) contains the bespoke user config farm
  proposed as the first migration target.
- [`/tasks/compfuzor/vars_base.tasks`](/tasks/compfuzor/vars_base.tasks) and
  [`/tasks/compfuzor/links.tasks`](/tasks/compfuzor/links.tasks) are the current
  declaration normalization and direct-effect seams.
