---
type: ImplementationBrief
title: Consumer config toolkit — linked inputs and local assembly
description: Bounded build direction following the human's consumer-first and permissive-toolkit decisions.
resource: /.design/config-user-target/build0.unknown.md
status: draft
generated: { by: model:unknown, at: 2026-09-08 }
verified: { by: unverified }
sources:
  - id: assessment
    resource: /.design/config-user-target/assessment0.unknown.md
    title: Reusable configuration tools, explicit consumer contexts
---

# Consumer config toolkit

Exact underlying author model is unavailable; `unknown` is intentional.
This records the next working slice, not the old draft3 implementation list.

## Human direction

- Interoperate with LINKS, including shared symlink machinery.
- Default to symlinked donor drop-in files and local assembly.
- Offer explicit copying of drop-ins, and whole assembled config copy/link.
- Status accepts matching copies and matching links equally; report local
  changes and disabled selections rather than insisting on one representation.
- Zim's two config channels and its two shell-loader block installs are
  different operations. Retain that distinction.
- Be permissive. Explicit copy/link commands authorize replacing selected
  regular files and symlinks. No ownership receipts or repeated force gates.
- Do not prune undeclared files, replace directories, write through a user
  output symlink into a donor, or escalate user operations unexpectedly.

## Bounded architecture

The existing filename-keyed CONFIGS and processor runtime remain the assembly
engine. A consumer context binds its compiled recipes to another root and input
set. No second user-only assembly implementation, no permanent mode database,
and no new dependency graph engine.

Add optional top-level CONFIG_CONTEXTS:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    dir: config
    subpath: zsh
    configs: [zimrc, zimenv]   # omitted means all compiled configs
    install: assemble        # assemble | copy | link
    dropins: link            # link | copy
    outputs:                 # optional precise per-config selectors
      zimrc:
        env: ZIM_CONFIG_FILE
        default: "${XDG_CONFIG_HOME}/zsh/zimrc"
      zimenv:
        env: ZIM_ENV_CONFIG
        default: "${XDG_CONFIG_HOME}/zsh/zimenv"
```

`dir` is a named consumer root (config/state/log/cache/bin/share) or an exact
path/structured `{env, default, suffix}` selector. Root expansion supports HOME
and standard XDG fallbacks without eval. System contexts use explicit absolute
roots or class roots, not ambient user selectors. Context names are identifiers;
scope is explicit metadata, not inferred from a name.

Compilation is a second pure filter over the existing compiled config result,
so the current compiler's user-owned modifications need not be touched.
It adds `spec.contexts`, BINS, status wrappers, and required module directories.
`sub_config.tasks` invokes it before config_publish. No user directories are
created at Ansible generation time.

Each compiled context contains:

```text
scope, root (selector), install, dropins,
configs: mapping of existing config IDs to {
  output: selector or {relative: path},
  inputs: [{source: canonical compiled input,
            relative: consumer-relative file path or glob directory}]
}
```

The original compiled config record remains authoritative for processor,
validation, block policy, apply, and canonical output. Inputs under ETC retain
their ETC-relative location. External inputs use
`inputs/<config-id>/<input-index>/<basename>` (directory basename for globs).
Outputs under ETC retain their relative location; external outputs use their
basename. Reject conflicting source-to-consumer mappings, output/input
collisions, unknown config/output IDs, invalid scope/defaults, and generated
command name collisions. Do not invent restrictions on ordinary trusted paths.

## Runtime surface

One raw TypeScript runtime at `bin/config/consumer.ts` consumes the deployment
spec, derives the deployment from its script location, and binds the selected
context. It imports `../links/delivery.ts` for copy/link behavior. This source
and deployment module layout must match.

Invocation protocol:

```text
consumer.ts --context NAME assemble [normal config.sh args]
consumer.ts --context NAME install [CONFIG]
consumer.ts --context NAME whole-copy [CONFIG]
consumer.ts --context NAME whole-link [CONFIG]
consumer.ts --context NAME dropins [--strategy copy|link] [CONFIG]
consumer.ts --context NAME status [CONFIG]
consumer.ts --context NAME inputs list|status [INPUT]
consumer.ts --context NAME inputs put INPUT SOURCE [NAME] [--strategy copy|link]
consumer.ts --context NAME inputs enable|disable|remove INPUT NAME
```

Generated tools for context `user`:

- `config-user.sh` → assemble (reuses `config.sh` flags/name selection).
- `install-config-user.sh` → install, the only composed toolkit leaf.
- `install-config-user-copy.sh` / `install-config-user-link.sh` → whole config.
- `install-config-user-dropins.sh` plus `-copy.sh` / `-link.sh` → drop-in refresh.
- `config-inputs-user.sh` → inputs.
- `status-config-context-user.sh` → status.

All variants are `compose: false`; the dispatcher has explicit scope and no
reserved subsystem-compositor name collision. Per-context compiled defaults
are overridden for an invocation by COMPFUZOR_CONFIG_INSTALL_STRATEGY and
COMPFUZOR_CONFIG_DROPINS_STRATEGY. Reuse CONFIG/context action guard machinery;
do not introduce the entire old cross-surface bypass matrix in this slice.

Generation opt-out is CONFIG_CONTEXTS_BYPASS; runtime opt-out is
COMPFUZOR_CONFIG_CONTEXTS_BYPASS. Existing broader config/BINS bypasses still
apply. Generation capability-by-capability suppression can follow the working
slice if needed; it must not be claimed as completed here.

## Behavior

### Assembly and default installation

`config-user.sh` only assembles. It never refreshes donor inputs. Build a
temporary resolved spec selecting this context's inputs/outputs; invoke the
existing config.sh with CONFIG_SPEC pointing to it. The same override must
reach processor leaves. Direct file and all existing processor kinds work.

An explicit assembly into an output currently represented by a symlink builds
a private candidate and replaces the symlink entry with a regular result;
it never edits the referent. This is a normal permissive mode switch.

Default install (`assemble`) seeds missing donor inputs, preserves existing
active/disabled entries regardless of representation, then assembles. Explicit
`dropins` refreshes currently declared donor entries in the chosen strategy,
preserving whether the user has disabled them. Donor disabled inputs are
included in the selectable catalog; initial seeding respects their disabled
state. User-local extra files in the input glob are real assembly inputs.

Whole copy/link only publishes the selected canonical outputs. It does not
refresh drop-ins or assemble them. A later explicit assembly changes that
choice back; a later explicit copy/link changes it again. No hidden remembered
mode. The ordinary install command follows its stated compiled/env default.

Input operations work on local directory entries (copies, links, including
dangling links), never on donor content. Explicit remove is allowed; automatic
pruning is not. Mutation rebuilds the affected consumer config; if rebuild
fails, report that the input change remains for inspection and retry (exit 4).

### Inspection

Status lists donor-to-consumer input relationships, actual copy/link, and local
enabled/disabled state. Matching copies and links are equally clean. Extra
local inputs are visible and accepted. Missing/different/dangling source or
destination states are reported. Disabled is a valid local selection, not drift.
Removed upstream copies may remain active: report them, do not silently prune.

For outputs, a matching donor copy/link is acceptable; a regular output matching
local assembly is also acceptable even when it differs from the donor. Avoid
claiming it is possible to infer the history of a regular file from its bytes.
`config-user.sh --check/--stdout` always describes local assembly specifically.
No evidence sidecars or general three-way history are required for this slice.

### Shared runtime essentials

Config candidate temps are registered immediately, output modes are retained,
and output replacement does not follow symlinks. Check/stdout use scratch temps
and do not require writable output directories. Validate all selected candidates
before committing any. No automatic sudo; a system context runs under an
explicitly privileged caller. Existing LINKS system routing remains separately
supported, while its user scope must not escalate.

## Checkpoint and verification

Demonstrate one compiled deployment against two scratch homes and a scratch
system context, all existing processors, a copied and linked drop-in side by
side, local edits/additions, local disable/enable, donor changes, whole-output
copy/link, return to assembly, and status. Exercise output mode retention,
symlink detachment, validation failure, empty inputs, missing/dangling inputs,
spaces in paths, XDG overrides, and foreign ambient DIR. Do not mutate live
Zim or install packages. Commit each coherent implementation stage.

Zim migration follows the working generic interface, including runtime config
path defaults, host registry discovery, and separate loader blocks. Keep
canonical donor contribution/reassembly tools distinct from consumer assembly.

## Cross-references

- [Assessment](/.design/config-user-target/assessment0.unknown.md): architectural
  reasons for consumer binding, shared LINKS, and distinct assembly/publication.
- [Existing assembly runtime](/files/config-run.sh) and
  [processors](/files/config-processor.sh): reuse rather than fork.
- [Existing LINKS runtime](/files/links/links.ts): source of shared link behavior.
- [Zim playbook](/zim.opt.pb): two config channels and distinct startup loaders.
