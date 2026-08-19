---
type: Design
title: Recorded link plans and scoped materialization
description: First design draft for replacing inline LINKS effects with recorded, scope-aware activation scripts and file-entry link declarations.
tags: [compfuzor, design, links, activation, systemd]
status: draft
generated: { by: llm:gpt56, at: 2026-08-19T17:12:57-04:00 }
sources:
  - id: link-script-prompt0
    resource: /.design/link-script/prompt0.md
    title: link-script quest prompt
    author: llm:opencode
  - id: compfuzor-architecture
    resource: /doc/arch.md
    title: Compfuzor architecture
  - id: bin-composition
    resource: /doc/bins.md
    title: Bin compositors and composers
---

# Recorded link plans and scoped materialization

## Thesis

`LINKS` should stop being an Ansible-time mutation API. It should become an
authoring API for a durable **link plan**: normalized records describing which
links a deployment owns, which activation scope materializes them, and how an
existing destination is treated.

The plan should generate four consumers from one source of truth:

1. system and user activation scripts;
2. generic drift reporting;
3. collision auditing across deployments;
4. conservative teardown.

File entries should contribute to the same plan. The convenient form is
`link: user` for file families where `link` is unused, while `links:` is the
unambiguous full form across all artifact families. `BINS.link` already means
"source this bin from another path," so it must not be reinterpreted.

The key boundary is:

> Ansible resolves author intent into records; generated scripts materialize
> those records in the target scope.

## Goals

- Record every activation-surface link before acting on it.
- Compose system links into `install.sh` and user links into
  `install-user.sh`.
- Preserve existing files, directories, and foreign symlinks by default.
- Give operators one named, selective overwrite escape hatch.
- Derive links from the exact resolved destination of `ETC_FILES`,
  `VAR_FILES`, and other artifact entries.
- Represent user paths without resolving them to the deploying user's home.
- Make install, status, collision checks, and removal agree about ownership.
- Replace watchman's bespoke config symlink farm with the generic mechanism.

## Non-goals

- This does not turn arbitrary filesystem mutations into link records.
- This does not make system and user installation happen in one privilege
  context.
- This does not retain silent compatibility for malformed legacy `LINKS`
  entries.
- This does not use `eval` to expand paths from a record.
- This does not let overwrite policy recursively delete directories.

## Findings that constrain the design

### LINKS currently mixes declaration and execution

Mappings are normalized early in
[`vars_base.tasks`](/tasks/compfuzor/vars_base.tasks#L144-L147), then
[`links.tasks`](/tasks/compfuzor/links.tasks#L18-L39) independently resolves
sources and destinations and invokes Ansible's `file: state=link`. The task
already says generated installers are the preferred house pattern
([`links.tasks`](/tasks/compfuzor/links.tasks#L2-L8)).

Not all existing links are activation surfaces. Some establish repository or
build topology needed later in the same play. For example,
[`repo_go.tasks`](/tasks/compfuzor/repo_go.tasks#L10-L22) creates a repository
`bin` link while processing repositories. Deferring such a link could break the
remaining run. The design therefore needs an explicit, narrow deploy-time
primitive rather than pretending every existing entry has the same lifecycle.

### File destinations have one authoritative resolution point

Filesystem entries can use `dest`, `destTemplate`, containered hierarchy
selection, and family-relative names. Their actual destination is currently
computed inside
[`fs_hierarchy.tasks`](/tasks/compfuzor/fs_hierarchy.tasks#L89-L135).
A generated link must consume that resolved destination. Reconstructing it in a
second Jinja expression would eventually disagree, especially for entries like
the README contributor whose `destTemplate` leaves its nominal family
([`common.yaml`](/vars/common.yaml#L691-L697)).

### Scope is composition metadata

`bin_composers` routes user leaves into `install-user.sh` and system leaves
into `install.sh`; subsystem compositors form a middle tier
([`bin_composers.py`](/library/filter_plugins/bin_composers.py#L64-L85),
[`bin_composers.py`](/library/filter_plugins/bin_composers.py#L135-L206)). An
authored leaf named `install-links.sh` would collide with the generated
subsystem compositor. Generated leaves therefore need distinct names.

### Runtime path syntax is consumer-specific

The fsh lookup deliberately emits `%h`/`%t` for systemd and literal
`${HOME}`/`${XDG_RUNTIME_DIR}` for shell consumers
([`fsh.py`](/library/lookup_plugins/fsh.py#L14-L31)). Link installers are shell
consumers. A JSON string containing `${HOME}` is not expanded merely by reading
it with `jq`, and evaluating arbitrary record text would be unsafe. Link plans
need a small, explicit path-template vocabulary.

### BINS already owns `link`

For BINS, `link` names a source to place under `BINS_DIR`, and `global` requests
the public-bin link
([`bins.tasks`](/tasks/compfuzor/bins.tasks#L41-L70),
[`bins_link.tasks`](/tasks/compfuzor/bins_link.tasks#L2-L14),
[`bins_link_global.tasks`](/tasks/compfuzor/bins_link_global.tasks#L11-L24)).
Making `BINS.link: user` mean activation scope would be an incompatible type
collision, not an ergonomic extension.

### The pipeline finalizes BINS too early

`gen_bins.tasks` currently runs before desktop and patch generators, even
though later generators can contribute BINS
([`compfuzor.includes`](/tasks/compfuzor.includes#L91-L103)). Link synthesis
will also contribute BINS and status reporters. All producers need to run before
one final composition pass.

### Bypass naming is inconsistent today

The outer include checks plural `LINKS_BYPASS`, the inner task checks singular
`LINK_BYPASS`, and persisted variables list only the singular form
([`compfuzor.includes`](/tasks/compfuzor.includes#L158-L165),
[`links.tasks`](/tasks/compfuzor/links.tasks#L18-L27),
[`common.yaml`](/vars/common.yaml#L95-L127)). Runtime action scripts already
use singular `COMPFUZOR_LINK_BYPASS`, consistent with the documented two-layer
namespace ([`subsys.md`](/doc/subsys.md#L259-L271)).

## Domain model

Use these terms consistently:

| Term | Meaning |
|---|---|
| link intent | An authored top-level or per-entry request before resolution. |
| link plan | The complete normalized record for one deployment. |
| link record | One owned `source -> destination` relationship. |
| scope | The activation identity and privilege domain: `system` or `user`. |
| materialization | Creating or updating a symlink from a record. |
| managed link | A destination symlink whose resolved target equals the record's source. |
| override | Any existing destination that is not the managed link. |
| owner | The deployment and record ID claiming a destination. |
| registry | A discoverable collection of plans used for cross-deployment audits. |

`scope` is not merely a path prefix. It chooses the compositor, privilege
boundary, runtime substitutions, registry, and status context.

## Authoring API

### Top-level LINKS

The full form remains explicit and expressive:

```yaml
LINKS:
  - id: modprobe-blacklist
    src: "{{ ETC }}/blacklist-efi-pstore.conf"
    dest: /etc/modprobe.d/blacklist-efi-pstore.conf
    scope: system
  - id: watchman-config
    src: "{{ ETC }}/watchman.json"
    dest:
      fsh: etc
      name: "{{ NAME }}/watchman.json"
    scope: user
```

Defaults:

- `scope: system`;
- `policy: preserve`;
- `state: present`;
- generated stable `id` when omitted;
- relative `src` remains relative to `DIR`, matching current authoring
  expectations;
- relative string `dest` remains relative to `DIR`.

A destination may be either a literal path or a structured fsh destination.
For user scope, the structured form is preferred because it preserves the
meaning of the path until activation.

Mapping shorthand may remain for simple system records:

```yaml
LINKS:
  /etc/modprobe.d/example.conf: "{{ ETC }}/example.conf"
```

It normalizes to the full form before plan generation.

### Per-entry shorthand

For `ETC_FILES`, `VAR_FILES`, and other file families where `link` is not
already defined:

```yaml
ETC_FILES:
  - name: watchman.json
    json: { enforce_root_files: true }
    link: user
```

This means:

- source is the exact resolved destination of this file entry;
- scope is `user`;
- destination is the same family, deployment name, and entry-relative path in
  the user fsh hierarchy;
- policy is `preserve`.

For watchman, this resolves semantically to:

```text
/etc/opt/watchman-main/watchman.json
  -> user fsh(etc)/watchman-main/watchman.json
  -> ${HOME}/.config/watchman-main/watchman.json at shell activation
```

The shorthand should be deliberately narrow. Custom destinations and multiple
links use `links:`:

```yaml
ETC_FILES:
  - name: example.desktop
    links:
      - scope: user
        dest:
          fsh: share
          name: applications/example.desktop
      - scope: system
        dest: /usr/local/share/applications/example.desktop
```

`links:` is canonical on every artifact family. `link: user` desugars to one
`links:` element only on families where `link` has no prior meaning.

For BINS, retain existing `link` behavior and use `links:` for activation
links:

```yaml
BINS:
  - name: example
    src: example.sh
    links:
      - scope: user
        dest:
          fsh: global-bins
          name: example
```

Existing `global` can migrate to this form later, but this design need not
remove it in the first implementation.

### Explicit deploy-time links

Introduce `DEPLOY_LINKS` for links required as inputs to later Ansible tasks:

```yaml
DEPLOY_LINKS:
  - src: "{{ BINS_DIR }}"
    dest: "{{ REPO_DIR }}/bin"
```

`DEPLOY_LINKS` is intentionally not recorded as activation ownership and does
not participate in generic teardown. New user surfaces, system integration
links, dotfiles, and public-bin links belong in `LINKS`; only generation
topology belongs in `DEPLOY_LINKS`.

This makes the exception visible and lets `LINKS` fully adopt deferred
semantics without carrying a permanent `phase` switch on every record.

## Canonical record

Generate `{{ DIR }}/etc/links.json` as versioned data:

```json
{
  "version": 1,
  "deployment": {
    "id": "watchman:main",
    "name": "watchman-main",
    "dir": "/srv/watchman-main"
  },
  "links": [
    {
      "id": "etc:watchman.json:user",
      "origin": "ETC_FILES[watchman.json].link",
      "scope": "user",
      "source": { "path": "/etc/opt/watchman-main/watchman.json" },
      "destination": {
        "template": "${HOME}/.config/watchman-main/watchman.json",
        "parameters": ["HOME"]
      },
      "policy": "preserve"
    }
  ]
}
```

Design requirements:

- `version` is mandatory and rejected when unsupported.
- IDs are stable across regeneration and unique within the plan.
- `origin` makes generated records explainable but is not identity.
- resolved deploy paths are absolute.
- runtime paths declare allowed parameters separately from their template.
- records retain authored policy rather than baking it into shell text.
- output ordering is deterministic for useful diffs.

The installer supports only exact, anchored parameter substitutions generated
by fsh: `${HOME}` and `${XDG_RUNTIME_DIR}`. It substitutes prefixes directly;
it never feeds record content through shell evaluation. An unknown parameter,
an unanchored variable expression, or a missing required runtime variable is a
hard error.

This model lets fsh remain the authority for path conventions: synthesis calls
the lookup with shell placeholders, records its output and allowed parameters,
and runtime performs only safe substitution. `%h` and `%t` remain systemd-only
forms and do not enter link plans.

## Generation pipeline

Create `gen_links.tasks` as a synthesis pass with no host-side link effects.
In the architecture vocabulary, normalization should publish `spec_links`,
while synthesis should publish `_syn_links` and merge its artifact
contributions. That follows the `raw -> norm/spec -> syn -> apply` boundary in
[`pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md#L70-L138)
rather than allowing `gen_links.tasks` to become another combined normalize,
validate, merge, and apply task.

The links domain should expose `LINKS_REQUESTED`, `LINKS_BYPASSED`,
`LINKS_VALID`, and `LINKS_ACTIVE`. `LINKS_BYPASS` participates in that one
activation contract; downstream transform and synthesis work gates on
`LINKS_ACTIVE`.

The relevant compile order should become:

```text
all domain/artifact generators
  -> resolve artifact destinations and collect link intents
  -> gen_links (normalize, validate, emit plan + consumers)
  -> gen_status (now sees the links reporter)
  -> gen_bins (single final compositor pass)
  -> filesystem materialization of files and BINS
```

The implementation should extract one artifact-destination resolver used by
both `fs_hierarchy.tasks` and link contribution. Do not copy the current Jinja
expression into `gen_links.tasks`.

`gen_links.tasks` contributes:

- `ETC_FILES`: `links.json`;
- `ENV`: `LINKS_JSON={{ DIR }}/etc/links.json`;
- `ENV_LIST`: `LINKS_JSON`;
- `PKGS`: `jq`;
- `BINS`: system/user installer and remover leaves;
- `STATUSES`: `status-links.sh`.

Generated leaf names avoid compositor collisions:

| Leaf | Scope | Subsystem | Generated route |
|---|---|---|---|
| `install-link-records-system.sh` | system | `links` | `install-links.sh` -> `install.sh` |
| `install-link-records-user.sh` | user | `links` | `install-links-user.sh` -> `install-user.sh` |
| `remove-link-records-system.sh` | system | `links` | standalone initially |
| `remove-link-records-user.sh` | user | `links` | standalone initially |

The first implementation should keep removal leaves standalone. A later change
can add `remove` to `BIN_ACTIONS` and obtain `remove.sh` / `remove-user.sh`
composition for all subsystems, rather than adding a links-only compositor
special case.

If one scope has no records, do not emit its leaf. Empty plans need not activate
the subsystem.

## Materialization semantics

For each record in the selected scope:

1. Resolve approved runtime path parameters.
2. Require an existing source unless the record explicitly opts into a
   dangling link.
3. Check for duplicate destinations in the local plan.
4. Check registered plans for a foreign claim on the destination.
5. Create missing parent directories only when their existing ancestors are
   directories and the scope permits it.
6. Classify the destination with both `-e` and `-L`.
7. If absent, create the symlink.
8. If it is a symlink resolving to the intended source, report idempotent
   success.
9. Otherwise preserve it as an override unless overwrite policy selects this
   record.
10. When selected for overwrite, remove only a non-directory destination with
    `rm -f`, then create the link. Never use `rm -rf`.

Comparison should use normalized absolute targets so equivalent relative and
absolute symlinks are treated as managed. The watchman installer already
demonstrates the important `-e || -L` and normalized-target checks
([`watchman.srv.pb`](/watchman.srv.pb#L171-L190)).

Parent creation is part of materialization because user surfaces such as
`~/.config/<name>` and `~/.local/bin` may not exist. It must not alter an
existing parent's ownership or mode.

### Don't-stomp and overwrite

Default `policy: preserve` means any regular file, directory, foreign symlink,
or dangling foreign symlink is an operator/user override and remains untouched.

Use `COMPFUZOR_LINK_OVERWRITE` as the link analogue of
`COMPFUZOR_ENV_OVERWRITE`:

- `1`, `true`, `y`, `yes`, or `*`, case-insensitive: select every record;
- otherwise: comma-separated, case-insensitive glob patterns matched against
  stable record IDs.

Matching IDs rather than paths avoids parsing commas or shell metacharacters in
destinations and gives diagnostics a stable name. A selected directory still
fails safely; overwrite is not permission for recursive deletion.

The action leaves declare `bypass: LINK`, producing the established
`COMPFUZOR_LINK_BYPASS` runtime guard. At generation time, canonicalize the
Ansible flag as `LINKS_BYPASS`: it suppresses link-plan contribution and link
consumer generation. Retire singular playbook `LINK_BYPASS` after migrating
current callers rather than perpetuating both names.

## Status, collision detection, and registry

`status-links.sh` reads the same plan and classifies each record as:

- `OK managed`;
- `OK override` for a preserved non-managed destination;
- `DRIFT missing`;
- `DRIFT dangling managed link`;
- `DRIFT wrong link` when policy requires ownership rather than preservation;
- `ERROR source missing`;
- `COLLISION` when multiple plans claim the same destination.

Whether an override is healthy or drift is policy, not reporter-specific
logic. `preserve` treats an override as healthy but visible; a future
`required` policy may classify it as drift without automatically deleting it.

Cross-playbook collision detection requires discoverability beyond a plan under
one `DIR`. Generate a second copy of each plan into a well-known data registry:

```text
system: {{ ETCS_DIR }}/compfuzor/link-plans/<deployment-id>.json
user:   ${XDG_STATE_HOME:-${HOME}/.local/state}/compfuzor/link-plans/<deployment-id>.json
```

The system registry copy is generated data, not link materialization. The user
registry copy is installed by the user activation leaf because its location is
user-specific. Installers audit all visible plans before applying records and
register their own plan only after local validation. Duplicate claims with the
same source can be reported as shared ownership but should still be explicit;
different sources are a hard collision and must not be overwritten.

Registry entries include the deployment ID and source-plan path. Teardown
removes its registry entry only after processing its owned records.

Concurrent activation should take a registry lock while checking claims,
materializing links, and publishing the plan. System and user registries have
separate locks because they are separate privilege domains.

## Teardown

Removal consumes the same plan and is intentionally asymmetric with install:

- remove a destination only when it is currently a symlink resolving to the
  recorded source;
- preserve regular files, directories, foreign links, and links changed after
  installation;
- do not remove parent directories in the first implementation;
- report preserved overrides and missing destinations without failing;
- remove the plan's registry entry after owned links are gone;
- support `COMPFUZOR_LINK_BYPASS` just like installation.

This ownership check is what recorded data adds: teardown can reverse exactly
the materialization it still owns without erasing later user decisions.

## Watchman as the first consumer

Watchman's `ETC_FILES` entry becomes:

```yaml
ETC_FILES:
  - name: watchman.json
    link: user
    json:
      root_files: [.git, .hg, .jj]
      enforce_root_files: true
      # existing ignore_dirs omitted
```

Then:

- delete the bespoke `install-user-etc.sh` leaf;
- let generated composition add the user link installer;
- remove the hand-written `config-link` branch from
  [`status-watchman.sh`](/files/watchman/status-watchman.sh#L74-L87) once the
  generic reporter is part of `status.sh`;
- retain watchman-specific config-content checks;
- separately migrate `install-cli-symlink.sh`, whose current `rm -rf` behavior
  violates the new don't-stomp policy
  ([`watchman.srv.pb`](/watchman.srv.pb#L158-L170)).

The config farm is the right first tracer bullet: global source, user fsh
destination, existing override semantics, composed user activation, status,
and teardown all exercise the design without requiring a system destination.

## Migration

Inventory existing `LINKS` before changing semantics and classify each entry:

| Class | Migration |
|---|---|
| user surface | keep in `LINKS`, add `scope: user` or move onto an artifact entry |
| system integration | keep in `LINKS`, default/system scope |
| public executable | use artifact `links:`; preserve legacy BINS fields temporarily |
| generation/build topology | move to `DEPLOY_LINKS` or eliminate through direct paths |
| malformed legacy shape | repair explicitly; do not guess |

Known health issue: list entries using `key`/`value`, such as
[`k3c.srv.pb`](/k3c.srv.pb#L7-L16), do not match the current executor's
`src`/`dest` access. Migration should reject these with a useful validation
error rather than preserve accidental behavior.

Known health issue: `repo_go.tasks` mutates `LINKS` as a mapping after the
early mapping-to-list normalization pass. Moving its generation-topology link
to `DEPLOY_LINKS` also removes this type instability.

Because the project is pre-1.0, prefer one clear semantic cutover with an
inventory-backed migration over compatibility branches in every consumer.

## Validation and tests

### Unit tests

- Normalize mapping shorthand and full records.
- Expand `link: user` from each supported artifact family.
- Preserve the exact resolved source for `dest` and `destTemplate` entries.
- Reject `link: user` on BINS with guidance to use `links:`.
- Produce stable IDs and deterministic plan ordering.
- Reject duplicate IDs, duplicate local destinations, unsupported scopes,
  unknown policies, unknown parameters, and relative resolved paths.
- Verify fsh shell templates for `HOME` and `XDG_RUNTIME_DIR`.
- Verify final bin composition routes system and user leaves correctly.

### Script integration tests

Run installers and removers in temporary homes/roots and cover:

- absent destination;
- already-correct absolute and relative symlinks;
- regular-file override;
- directory override;
- foreign and dangling symlink overrides;
- selective and all-record overwrite;
- overwrite refusal for directories;
- missing source;
- missing runtime parameter;
- parent creation and parent obstruction;
- safe teardown after a user changes the link;
- runtime bypass;
- same-source and conflicting-source registry claims;
- concurrent activation under the registry lock.

### Playbook integration tests

- Syntax-check and render a minimal system plan.
- Render a user plan and assert literal runtime placeholders survive Ansible.
- Exercise watchman's `link: user` tracer bullet with package/systemd effects
  bypassed.
- Verify `LINKS_BYPASS` emits neither plan consumers nor materialization.
- Verify `DEPLOY_LINKS` still exists before a later task that consumes it.
- Verify desktop/patch/link BINS all appear in final compositors.

## Implementation slices

1. Add normalized link-record and artifact-destination filters with unit tests.
2. Move BINS composition to the final producer boundary and lock that order
   with integration tests.
3. Add `gen_links.tasks`, `links.json`, and system/user install leaves.
4. Replace inline `LINKS` execution; introduce and migrate `DEPLOY_LINKS`.
5. Add status, registry collision checks, and conservative removal.
6. Migrate watchman's config farm and remove its duplicate status logic.
7. Inventory and migrate remaining link declarations by lifecycle class.
8. Resolve or document adjacent fsh convention issues before adding desktop
   shorthand; notably user `share` currently maps to `.local/usr/share`, not
   the conventional `.local/share`
   ([`fsh.py`](/library/lookup_plugins/fsh.py#L104-L120)).

Each slice should leave one authoritative path for the behavior it introduces;
do not run inline and recorded `LINKS` in parallel for the same declarations.

## Decisions and open questions

This draft recommends:

- `LINKS` means deferred activation links after migration;
- `DEPLOY_LINKS` is the explicit generation-time exception;
- `links:` is canonical and `link: user` is narrow sugar;
- records contain fsh-rendered, parameter-whitelisted shell templates;
- preserve is the default and overwrite matches stable record IDs;
- directories are never removed by overwrite;
- teardown removes only still-managed symlinks;
- BINS composition happens once, after all producers.

Questions to settle during implementation:

- Should explicit top-level user destinations require structured fsh form, or
  may callers provide a literal `${HOME}` template with a declared parameter?
- Should same-source claims from multiple deployments be allowed as shared
  ownership or rejected to keep teardown ownership singular?
- Should `required` be included in version 1 policy, or should version 1 expose
  only `preserve` plus operator-selected overwrite?
- Is the system registry rooted under `ETCS_DIR`, or should compfuzor establish
  a dedicated state hierarchy independent of each deployment type?
- Should removal become a general fourth composed BINS action immediately,
  instead of starting with standalone leaves?

The tracer bullet does not depend on all of these answers. Watchman's
preserve-policy user config link can validate the central record, path,
composition, and ownership model first.

## Cross-references

- [`prompt0.md`](/.design/link-script/prompt0.md) is the expanded quest this
  draft answers. It establishes recorded runtime data, per-entry ergonomics,
  don't-stomp behavior, and watchman as the driver.
- [`draft0.opencode.md`](/.design/link-script/draft0.opencode.md) is prior-wave
  design work supporting a canonical `links.json`, generic manager, and final
  producer ordering. This draft extends that direction with an explicit
  deploy-topology escape hatch, a registry shape, and safe runtime parameter
  substitution.
- [`draft0.glm5t.md`](/.design/link-script/draft0.glm5t.md) is prior-wave work
  emphasizing BINS composition, fsh shell paths, and the `BINS.link` naming
  collision. It differs on whether JSON should be authoritative; the expanded
  prompt's verification and teardown requirements make recorded data a firm
  choice here.
- [`arch.md`](/doc/arch.md#L400-L426) defines the phase, role, and effect
  vocabulary. Its current catalog describes `links_*` as host-effecting
  execution; this design introduces effect-free link transform/synthesis and
  moves materialization into generated BINS, so the catalog should be refined
  when the design is accepted.
- [`pipeline-and-intent-prefix-memo.md`](/doc/pipeline-and-intent-prefix-memo.md#L70-L138)
  supplies the `spec_links` / `_syn_links` lifecycle and domain activation
  contract used by the proposed pipeline.
- [`bins.md`](/doc/bins.md#L12-L95) is the normative compositor hierarchy. It
  explains both the system/user route and why generated leaves cannot occupy
  reserved `install-links[-user].sh` names.
- [`subsys.md`](/doc/subsys.md#L430-L444) confirms `LINKS` is already a
  subsystem contribution artifact with append merge behavior. Link synthesis
  can therefore use the normal contribution boundary rather than inventing a
  side channel.
