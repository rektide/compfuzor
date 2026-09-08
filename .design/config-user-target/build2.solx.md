---
type: ArchitectureCheckpoint
title: Consumer config donor and output toolkit
description: Working generic copy/link, seed, refresh, status, and local-input operations over reusable CONFIGS contexts and shared LINKS delivery.
resource: /.design/config-user-target/build2.solx.md
tags: [compfuzor, config, consumer-context, links, delivery, status]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
stale_after: 2026-10-08
sources:
  - id: prior-checkpoint
    resource: /.design/config-user-target/build1.solx.md
    title: Reusable CONFIGS consumer binding
  - id: architecture-assessment
    resource: /.design/config-user-target/assessment0.unknown.md
    title: Reusable configuration tools, explicit consumer contexts
---

# Consumer config donor and output toolkit

## Checkpoint

The generic toolkit now supports the complete operator-controlled cycle around
the context binding accepted in build1:

1. seed absent donor inputs, preserving existing local entries;
2. assemble locally with the canonical CONFIGS processors;
3. explicitly refresh donor inputs as copies or links;
4. publish a canonical whole output as a copy or link;
5. return from a whole link to local assembly by invoking `config-<context>.sh`;
6. inspect outputs, donor inputs, disabled choices, modifications, missing
   donors, and local additions;
7. directly put, enable, disable, or remove local inputs and rebuild the
   affected config.

No Zim, Mise, or live user configuration has been migrated.

## Declaration and defaults

The accepted binding gains only two policy defaults:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    configs: [zimrc, zimenv]
    install: assemble # assemble | copy | link
    dropins: link     # link | copy
```

`install: assemble` performs missing-only input seeding with the configured
drop-in strategy and then local assembly. `install: copy` and `install: link`
publish canonical whole outputs without refreshing inputs or assembling.

Runtime overrides do not create a preference database:

```bash
COMPFUZOR_CONFIG_INSTALL_STRATEGY=link install-config-user.sh zimrc
COMPFUZOR_CONFIG_DROPINS_STRATEGY=copy install-config-user-dropins.sh zimrc
```

`CONFIG_CONTEXTS_BYPASS=True` suppresses all generated context artifacts.
`COMPFUZOR_CONFIG_CONTEXTS_BYPASS=1` and `COMPFUZOR_CONFIG_BYPASS=1` skip only
the ordinary composed install dispatcher. Explicit assembly, copy, link,
refresh, and input commands remain explicit operator actions.

## Generated command API

For a context named `user`:

```text
config-user.sh [--list | --check | --stdout] [CONFIG]

install-config-user.sh [CONFIG]
install-config-user-dropins.sh [CONFIG]
install-config-user-dropins-copy.sh [CONFIG]
install-config-user-dropins-link.sh [CONFIG]
install-config-user-copy.sh [CONFIG]
install-config-user-link.sh [CONFIG]

config-inputs-user.sh list [CONFIG]
config-inputs-user.sh status [CONFIG] [--json | --json-array]
config-inputs-user.sh put INPUT SOURCE [NAME] [--strategy copy|link]
config-inputs-user.sh enable INPUT NAME
config-inputs-user.sh disable INPUT NAME
config-inputs-user.sh remove INPUT [NAME]

status-config-context-user.sh [CONFIG] [--json | --json-array]
```

`INPUT` is `CONFIG/INPUT_NAME`; a unique bare input name is also accepted.
Compiled glob names are stable input names. Direct file inputs use their numeric
index and do not take a destination basename.

Only `install-config-user.sh` composes into ordinary install orchestration. All
strategy variants, input tools, status, raw modules, and assembly commands are
`compose: false`. Scope metadata comes from the context rather than its name.

## Donor relationship and mutation behavior

The runtime combines two existing facts instead of compiling filesystem
contents:

- the original CONFIGS spec supplies canonical donor files/directories,
  patterns, and disabled suffixes;
- `bindContextConfigs()` supplies the selected consumer input/output paths.

Donor glob directories are enumerated at invocation time. Direct file inputs,
active glob entries, and disabled donor entries become relationships. A link
targets the declared donor directory entry, even when that donor entry is
itself a producer symlink. It is not rewritten to the final referent.

### Seed versus refresh

- **Seed** creates an entry only when neither its active nor disabled local name
  exists. A donor-disabled entry is initially disabled. Existing links, copies,
  edited files, foreign links, and disabled choices are preserved.
- **Refresh** explicitly replaces the selected regular file or symlink with the
  requested representation. It preserves whether the existing local entry is
  active or disabled. There is no force switch.
- If both active and disabled names exist, status reports a local conflict and
  refresh leaves both untouched.
- Empty existing donor directories create empty consumer directories and remain
  valid assembly inputs.
- Extra local inputs are not removed. Reassembly consumes them normally.

Copy/link replacement refuses directories and special files, uses same-directory
temporary entries and rename, and never copies through a destination symlink.
Source and destination cannot name the same path. Multi-file refresh is not a
global transaction: independent successful updates remain visible if another
relationship fails.

Input `put`, toggle, and remove operations mutate only local directory entries.
They never follow an entry into a donor. The affected config is rebuilt; if
rebuild fails, the explicit input mutation remains for inspection and retry and
the tool exits 4.

## Status model

Output and input rows remain distinguishable in human, JSONL, and JSON-array
formats.

For declared donor inputs:

- a byte-matching regular file is `copy / ok`;
- a symlink targeting the declared donor entry is `link / ok`;
- either can be enabled or disabled without drift;
- differing bytes or another link target are reported as modified;
- missing and dangling donors, unsupported entries, and simultaneous
  active/disabled names are explicit.

Local files absent from the current donor catalog are reported as local and are
accepted. A retained regular copy cannot truthfully be attributed to a removed
donor without a receipt, so status does not claim that provenance. A dangling
link into the donor directory does expose its relationship and is reported as
donor-missing.

For whole outputs, matching donor copies and links are healthy. A regular output
that differs from the donor but matches a fresh local assembly check is also
healthy as `assembly`. `config-user.sh --check` remains the specific answer to
“what would local reassembly change?”

Status exits 0 for healthy/accepted state, 1 for local drift or conflicts, and 2
for donor/source errors. Input mutation rebuild failure retains its separate
exit 4.

## Shared LINKS seam and privilege correction

[`links/delivery.ts`](/files/links/delivery.ts) is now the import-safe entry
inspection and atomic link replacement implementation used by both the existing
LINKS manager and the config toolkit. It also provides the local atomic copy
sibling. The existing LINKS parser, manifest resolution, `preserve`/`fail`/
`replace` policy, ID filtering, and status vocabulary remain in
[`links/links.ts`](/files/links/links.ts).

This is intentionally narrower than making CONFIGS use the LINKS manifest as
its path authority: context binding already resolves consumer paths, while
explicit config refresh has a deliberately permissive replacement contract.
Sharing the actual classification/mutation primitive avoids a second symlink
implementation without conflating the two policies.

Installed compatibility remains `bin/links.ts`; a thin
[`files/links.ts`](/files/links.ts) facade preserves it while source and deployed
module layouts both use `links/links.ts` plus `links/delivery.ts`.

User-scope LINKS mutation is now intrinsically non-escalating:

- `--sudo auto` never routes a user record through sudo;
- explicit `--sudo always` (including bare `--sudo`) is rejected before a
  user-scope mutation and never invokes sudo;
- system-scope auto/always/never behavior is unchanged.

The config toolkit never invokes sudo for either scope. A system context must be
run by a caller that already has the required authority.

## Build1 review fixes

- Context selection is lazy enough for the requested operation. `--list`
  resolves no paths, named operations bind one recipe, and default operations
  bind only context-selected `apply: true` recipes.
- Context binding moved into import-safe
  [`config/context.ts`](/files/config/context.ts). Both assembly and delivery use
  its exported context/name/selector authority.
- The thin [`config-context.ts`](/files/config-context.ts) facade uses async
  realpath, derives deployment/spec defaults from itself or the explicit runner,
  forwards INT/HUP/TERM to the child process group, and removes the bound spec
  after child exit.
- Missing glob directories and genuine enumeration/sort failures now abort the
  shared config runner before output staging. Empty existing directories remain
  valid.
- An equal-byte output symlink now explains that `--check` plans to detach it to
  a regular assembled output.

## Verification

The rendered toolkit integration covers:

- one deployment, two independent user XDG roots, and an exact system scratch
  context, all with spaces;
- active and donor-disabled seeds, empty directories, direct files, runtime glob
  enumeration, matching copy/link mixtures, local edits and additions;
- missing and dangling donors, active/disabled conflicts, refresh preserving
  disabled state, permissive edited-file replacement, and directory refusal;
- input list/status/put/enable/disable/remove, including retained mutation and
  exit 4 after failed validation;
- whole copy, whole link, strategy environment overrides, and return to local
  assembly;
- output assembly health, JSON status, runtime/generation bypasses, no config
  sudo invocation, and source/deployed TypeScript imports;
- an actual generated `bin/links.ts` using the same deployed delivery module;
- compositor output proving only the ordinary context install joins install
  orchestration.

Existing LINKS tests cover policies, source/runtime roots, ID filters, audit,
atomic system sudo routing, and user-scope sudo rejection. The stale empty-status
assertion now matches the established silent clean selection; its suite reports
six passes.

## Remaining limitations

- Generation can suppress the whole context toolkit, but not individual copy or
  link variants yet.
- Strategies are invocation/playbook policy only; there is no persistent mode
  database.
- There are no receipts, automatic pruning, inferred provenance for regular
  local extras, or all-user enumeration.
- Delivery refresh is intentionally per relationship rather than a multi-file
  rollback ledger.
- Direct file inputs can be put or removed, but enable/disable applies only to
  glob inputs with a disabled suffix.
- SIGTERM cleanup is tested for the context-to-shell assembly child. SIGKILL and
  arbitrary process death cannot promise cleanup, and no broader cancellation
  framework was added.
- Zim loader blocks and application cache rebuilds are outside CONFIGS assembly
  and remain unmigrated.

## Proposed next checkpoint: Zim, then Mise

Do not transplant the current Zim `install-user` body unchanged. It currently
mixes donor mutation with user cache construction. First trace and separate:

1. canonical donor initialization and contribution management;
2. canonical `zimrc` and `zimenv` recipe maintenance;
3. consumer drop-in seed/refresh and local assembly;
4. user-specific Zim cache/build activation.

Then declare both Zim channels in one user context, default donor drop-ins to
links, assemble both into the invoking user's XDG/Zsh paths, and retain explicit
copy/link whole-output tools. Treat `.zshrc` and `.zshenv` loader blocks as two
separate block-in-file artifact installs, not as CONFIGS recipes or a copied
aggregate.

After the Zim operational split is proven, assess Mise against the same generic
toolkit. Migrate only the ownership relationships that match—do not force a
native drop-in consumer, a managed loader block, and a generated aggregate into
one lifecycle.

## Cross-references

- [`build1.solx.md`](/.design/config-user-target/build1.solx.md) records the
  accepted assembly and binding foundation.
- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  compiles defaults, commands, statuses, module directories, and collision
  checks.
- [`config/toolkit.ts`](/files/config/toolkit.ts) implements the generic runtime
  relationship and command API.
- [`config_context_toolkit.test.py`](/tests/integration/config_context_toolkit.test.py)
  is the rendered end-to-end proof.
- [`links_status.test.py`](/tests/integration/links_status.test.py) verifies
  retained LINKS status/policy behavior and corrected privilege routing.
