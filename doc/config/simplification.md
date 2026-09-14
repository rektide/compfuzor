---
type: SimplificationPlan
title: Simplifying Compfuzor configuration internals
description: Delete transitional renderers and compiler rewrites while preserving the working context, delivery, status, and domain contracts.
resource: /doc/config/simplification.md
tags: [compfuzor, config, zim, block-in-file, vite-plus, simplification]
status: draft
generated: { by: model:unknown, at: 2026-09-13 }
verified: { by: unverified }
stale_after: 2026-10-13
sources:
  - id: toolkit
    resource: /doc/config/consumer-toolkit.md
    title: Current consumer configuration contract
  - id: deployment
    resource: /doc/config/log.md
    title: Live deployment and runtime packaging evidence
  - id: block-in-file
    resource: https://github.com/jauntywunderkind/block-in-file/blob/main/README.md
    title: Managed block read, envsubst, validation, and additive capabilities
---

# Simplifying Compfuzor configuration internals

## Position

The current implementation works, is tested, and is live. It is also harder to
understand than it should be. Several rounds solved real behavioral problems by
adding layers before the final shape was visible. The next work should remove
those transitional layers—not introduce another generalized framework.

Preserve these product contracts:

- one configuration recipe can bind to different user/system contexts;
- `user` is the ordinary default and playbooks may choose another;
- one fixed action-command set, with runtime context and strategy selection;
- linked or copied inputs, local assembly, and whole-output publication;
- status accepts healthy copies and links and explains local/weird states;
- explicit operations are permissive; directories and donor aliases remain the
  small essential refusal cases;
- no automatic pruning or ownership database;
- LINKS owns its durable declaration lifecycle while sharing delivery effects;
- Zim's dual channels/caches/loaders remain Zim behavior;
- Mise's independent blocks remain independent.

Everything else is open to deletion.

## 1. Delete the custom Zim substitution engine

### What is wrong now

[`files/zim/activation.ts`](/files/zim/activation.ts) currently:

1. reads `zimrc.zsh` / `zimenv.zsh` template files;
2. finds custom `@@ZIM_*@@` tokens;
3. checks token count and unknown tokens;
4. replaces each token with a safely quoted value;
5. passes the resulting bytes to `block-in-file` over stdin;
6. repeats the same projection during status so installed bytes can be compared.

`block-in-file` is therefore reduced to a block writer even though it already
owns input transformation (`--envsubst`), insertion, byte-exact extraction
(`--read`), atomic writes, and validation. Compfuzor created a second template
language solely to feed a tool that already has substitution.

This is the clearest current simplification opportunity.

### Better shape

Use ordinary environment placeholders in the two Zim loader templates and let
`block-in-file` transform them:

```text
COMPFUZOR_ZIM_TEMPLATE_CACHE_HOME
COMPFUZOR_ZIM_TEMPLATE_CONFIG_OUTPUT
COMPFUZOR_ZIM_TEMPLATE_LEGACY_PATTERN
COMPFUZOR_ZIM_TEMPLATE_CONTROLLER
COMPFUZOR_ZIM_TEMPLATE_EMERGENCY_MODULE
```

Invoke it with single-pass substitution and a narrow allow-list expressed
through its exclusion regex:

```bash
block-in-file \
  --envsubst=non-recursive \
  --envsubst-exclude='^(?!COMPFUZOR_ZIM_TEMPLATE_).*$' \
  -n "$block" -C true -i "$template" -o "$startup"
```

The exclusion is important: loader bodies intentionally contain runtime shell
variables such as `$ZIM_HOME` and `$ZIM_CONFIG_FILE`; undefined envsubst values
otherwise become empty strings. Only the dedicated template namespace should be
expanded.

Compfuzor may still need one small `zshQuote()` function to encode paths as Zsh
literals before placing them in the environment. It should delete token scanning,
token-count enforcement, replacement loops, unknown-token regexes, and custom
newline normalization.

For status, ask `block-in-file` to install the projected block into a temporary
empty file, then read it back with `--read`; compare that projection with the
live block. This is less efficient than direct string replacement but removes a
language and keeps install/status semantics in the tool that owns the format.
If this proves too clumsy, add a small upstream “render input” operation to
block-in-file rather than rebuilding substitution in Compfuzor.

### Evidence before removal

- user and explicit system loader paths containing spaces and quotes;
- all runtime `ZIM_*` overrides still win after the block is sourced;
- anonymous `zimenv` leaks no variables/functions;
- emergency path and legacy normalization remain correct;
- install and status produce/read identical block bytes;
- malformed or missing template input fails visibly.

## 2. Stop emitting an old command model and rewriting it

**Completed in the repository on 2026-09-14.** `config_compile.py` now emits
the final internal runner, processor, processor leaves, and recipe links
directly. `config_context_compile.py` no longer contains
`_internalize_config_bins()` or string/path rewrite knowledge. Legacy
per-recipe and toggle wrappers are not emitted; canonical enable/disable remains
available through the fixed `config-inputs.sh --context canonical` interface.

### What is wrong now

[`config_compile.py`](/library/filter_plugins/config_compile.py) still emits the
old runtime surface (`config.sh`, processor wrappers, per-recipe commands, and
per-recipe status commands). Then
[`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
calls `_internalize_config_bins()` to:

- rename old paths;
- remove obsolete public commands;
- rewrite command strings;
- neutralize bypass on the renamed internals;
- emit the actual fixed action surface.

That is a migration adapter running inside every compilation. It makes both
files lie slightly: the first does not describe final output, and the second
must know exact strings produced by the first.

### Better shape

Split responsibilities directly:

```text
compile_config_recipes()
  -> normalized recipes, remotes, required dirs/packages

compile_config_runtime()
  -> final internal runner/processors, built JS bundle, fixed action symlinks,
     status record, and canonical/default contexts
```

`config_compile.py` should stop emitting legacy BINS entirely.
`config_context_compile.py` (or a renamed final-runtime compiler) should emit the
current shape directly. Delete `_internalize_config_bins()` and every string
replacement it contains.

This does **not** mean porting Python to TypeScript. These are Ansible controller
filters. The simplification is removing a translation step, not changing the
controller language.

### Evidence before removal

- exact generated bin/spec snapshots before and after;
- fixed action symlinks and internal processor links are unchanged;
- context-free canonical CONFIGS still assemble during playbook execution;
- remote/toggle rebuilds use the fixed command bundle;
- bypass remains only at typed ordinary-install boundaries;
- no per-context/per-recipe wrappers return.

## 3. Finish the Vite+ deployment boundary

CONFIG, Zim, LINKS, and config-remote now dispatch through one built
`compfuzor-runtime.mjs` artifact while retaining domain-grouped source and
stable command aliases.
Remaining raw TypeScript deployments are separate legacy surfaces:

- kernel status reporters;
- Repart/Mkosi runtime;
- MCP drop-in adapters.

Move them one domain at a time into the existing Vite+ multi-entry build. Each
slice should replace raw BINS records with one built executable and prove its
embedded/imported use case. Do not create another package, bundler, or build
configuration per domain.

The target-side rule should become simple and testable:

> Compfuzor deploys shell scripts, data/spec files, and built JavaScript—not
> Python plugins or TypeScript source.

## 4. Reduce specification overlap only after the first two deletions

`config.spec.json`, `zim.spec.json`, and `links.json` are separate because they
express different contracts. Do not merge them into a universal plan.

After deleting custom substitution and compiler rewriting, inspect duplication
again. Likely safe improvements include:

- one public compiled path-selector module on the controller;
- one runtime context-selection helper (already shared by CONFIG and Zim);
- Zim references to config-context outputs instead of repeated resolved values
  where no independent Zim meaning exists.

Do not generalize Zim channels, systemd scopes, Rust installs, or status rows to
make the JSON documents look symmetrical.

## 5. Keep user-facing output concise

The source modules were recently split into coherent responsibilities and all
Node CLIs now use `node:util.parseArgs`. Preserve that improvement.

Further usability work should be observational rather than architectural:

- one-line synopsis before detailed status tables;
- action-specific examples in `--help`;
- `list` output that names context, recipe, destination, and current
  representation without requiring JSON;
- errors that name the selected context/action before the stack trace;
- a generated-command inventory available without reading `bin/` manually.

Avoid aliases for every combination and avoid an omnibus interactive wizard.

## 6. Deliberately prune proven migration residue

No-prune remains the automatic policy. A human may still deliberately remove
artifacts proven unreachable after a successful migration. The residue found
during this migration is recorded in
[`log.md`](/doc/config/log.md#migration-residue-observed-before-the-explicit-prune).

Before manual removal:

1. verify no current command symlink or generated compositor references it;
2. run current direct and aggregate status successfully;
3. remove only the enumerated files/directories;
4. rerun status and command help;
5. record the exact deletion in the deployment log.

This is a migration operation, not a precedent for automatic reconciliation.

The enumerated 2026-09-13 Zim/Mise residue has now been removed following this
procedure. See the [deployment log](/doc/config/log.md#deliberate-migration-prune).
The automatic no-prune policy remains unchanged.

## Recommended order

1. Validate a shared managed-block provider before replacing Zim projection.
2. Use the attributed read-only runtime catalog to inspect current actions and
   flow order; legacy shell compositors remain execution authority.
3. Introduce native plural `composition` declarations through ordinary tracer
   cases, beginning with global-bin LINKS.
4. Migrate remaining TypeScript domains into the one Vite+ runtime one domain
   at a time.
5. Reassess spec duplication only after those deletions and tracers.

The test for every step is the deletion test: if removing the layer merely moves
the same complexity elsewhere, stop. If it eliminates a language, translation,
or interface that callers had to understand, keep the simplification.

## Cross-references

- [`README.md`](/doc/config/README.md) is the short entry point this plan was
  missing.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) defines behavior that
  simplification must preserve.
- [`log.md`](/doc/config/log.md) records the live proof and stale artifacts.
- [`command0-review0.solx.md`](/design/config-context/command0-review0.solx.md)
  records transaction, bypass, status, and stdout corrections that must not be
  accidentally removed as “complexity.”
- [`systemd-links0.solx.md`](/design/install-context/systemd-links0.solx.md)
  explains why shared copy/link delivery does not justify universal context or
  install machinery.
