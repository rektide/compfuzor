---
type: ArchitectureCheckpoint
title: Build 5 context semantics review
description: Close explicit alias precedence, context-correct Zim loader projection, and contributor command naming gaps without moving machinery into core config/install/build.
resource: /.design/config-user-target/build5-review0.solx.md
tags: [compfuzor, zim, contexts, loaders, aliases, contributors, verification]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-11 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-11 }
stale_after: 2026-10-11
sources:
  - id: build5
    resource: /.design/config-user-target/build5.solx.md
    title: Context-aware Zim installation surface
  - id: operator-guide
    resource: /doc/config/consumer-toolkit.md
    title: Consumer configuration toolkit
---

# Build 5 context semantics review

## Outcome

The three parent-review gaps are closed:

1. Explicit `--context` now prevents alias inference entirely. A valid explicit
   context succeeds even though the invoked basename is unsupported or names an
   undeclared context.
2. Both loader blocks now contain safely quoted defaults for their selected
   activation. User and explicit system blocks work with all `ZIM_*` selectors
   unset, while runtime overrides still win.
3. Contributors now expose scope-neutral `install-zimfw.sh`; explicit user
   scope metadata composes it into `install-user.sh` without encoding scope in
   the leaf filename.

No generalized channel map, core config/install/build abstraction, generated
command aliases, compatibility alias, or live deployment was added.

## Why `zim.spec.json` v2

Loader source semantics changed: the two ETC artifacts are templates rather
than bytes copied verbatim into startup files. Keeping v1 while silently
reinterpreting `zimrcLoader` and `zimenvLoader` would hide that change and force
the runtime to infer legacy and emergency paths from directory layout.

The bounded v2 expansion makes the actual inputs explicit:

```text
canonical.zimrcLegacy: string[]
canonical.zimenvLegacy: string[]
canonical.zimrcLoaderTemplate: string
canonical.zimenvLoaderTemplate: string
canonical.emergencyModule: string
```

The compiler derives these from canonical playbook/deployment paths. The
existing `zimrc`, `zimenv`, `controller`, `registry`, and `blockPrefix` fields
remain explicit. Runtime v1 compatibility is intentionally absent because no
v1 deployment was made; an old spec fails with its observed version, expected
version 2, and rerender guidance.

This is not a generalized loader schema. It remains a fixed two-channel Zim
contract.

## Exact loader approach

### Content authority

[`zim.opt.pb`](/zim.opt.pb) remains the single Zsh content authority through two
specialized templates:

```text
DIR/etc/zimenv.zsh
DIR/etc/zimrc.zsh
```

They use only the fixed placeholders required by the existing dual-channel
semantics:

```text
@@ZIM_CACHE_HOME@@
@@ZIM_CONFIG_OUTPUT@@
@@ZIM_LEGACY_CONFIG_PATTERN@@
@@ZIM_CONTROLLER@@
@@ZIM_EMERGENCY_MODULE@@   # zimrc only
```

[`zim/install.ts`](/files/zim/install.ts) resolves the selected activation and
projects these templates. Every substituted path is encoded as a single-quoted
Zsh literal with embedded quotes escaped; NUL is rejected. Required placeholders
must occur exactly once and unknown Zim placeholders fail. Tests execute paths
containing spaces and apostrophes.

The projector removes one final template newline because `block-in-file --read`
returns block contents without that boundary newline. This was the cause of the
intermediate status mismatch. Install and status now compare the same exact
projection.

### Installation and status

Install projects both loaders before config mutation, then passes the projected
bytes to `block-in-file` over stdin. It installs:

```text
<context loader_root>/.zshenv  block <NAME>-zimenv
<context loader_root>/.zshrc   block <NAME>-zimrc
```

Status resolves the same context and reruns the same projector before reading
the named block. It does not compare an installed block to unresolved template
bytes.

### Preserved channel semantics

- `zimenv` remains an anonymous function scope. Its projected defaults and
  temporary `ZIM_HOME`/`ZIM_CONFIG_FILE` do not leak, and the temporary `zimfw`
  function is removed.
- `zimrc` remains ordinary global shell context and retains emergency loading,
  cache freshness checks, controller initialization, and autosuggestion setup.
- With selectors unset, each loader uses its selected context's embedded config
  and cache paths.
- `ZIM_ENV_HOME`, `ZIM_ENV_CONFIG`, `ZIM_HOME`, and `ZIM_CONFIG_FILE` continue
  to override those embedded defaults at source time.
- Values matching any entry in the channel's explicit legacy list normalize to
  that activation's resolved config output, not a hardcoded user destination.

The rendered integration proof relocates `zimenvLoaderTemplate` and
`emergencyModule` independently and adds legacy paths found nowhere else in the
deployment. Successful projection, emergency sourcing, normalization, and clean
status therefore demonstrate that runtime behavior reads v2 fields rather than
deriving sibling paths.

## Alias precedence correction

`resolveSettings` calls `aliasContext` only when `options.context` is absent.
Tests cover all four cases:

- valid manual alias beats a conflicting environment context;
- explicit context beats a valid alias;
- explicit context succeeds through an undeclared-context alias;
- explicit context succeeds through an unsupported basename.

Without an explicit context, unsupported and undeclared aliases still fail with
guidance. Compfuzor still generates only the base command; aliases in tests and
the retained demo are created manually after the render is inspected.

## Contributor command rename

[`gen_zim.tasks`](/tasks/compfuzor/gen_zim.tasks) now emits:

```text
bin/install-zimfw.sh       scope: [user]
bin/install-user.sh        generated compositor -> install-zimfw.sh once
```

It emits no `install-user-zimfw.sh` alias or file. `install-zimfw.sh` discovers
the host as before and accepts/forwards only `--context NAME` or
`--context=NAME`; it ignores other package-compositor arguments. The explicit
context is forwarded to `install-zim-context.sh`, while
`COMPFUZOR_ZIM_CONTEXT` naturally remains the
effective selection when no flag is provided.

## Installed command tree

The Zim host's generated activation surface remains:

```text
etc/zim.spec.json
bin/install-zim.sh
bin/status-zim.sh
bin/zim/install.ts
```

Its explicit noncomposed role commands remain:

```text
bin/install-zim-context.sh
bin/install-zim-donor.sh
```

The host recipe also writes the two ETC loader templates. No context alias,
context-specific installer, or loader/cache/registry leaf is generated. The
nine generic config operator wrappers per context remain available and are not
redesigned by this review.

## Commits

- `3cdb4e5a` — `zim: let explicit context bypass alias inference`
- `638919c9` — `zim: project context loaders and neutralize contributor command`
- `ec95fc34` — `tests: prove explicit Zim v2 loader sources`
- `39c2f218` — `docs: describe explicit Zim v2 loader projection`
- `c3b11f17` — `tests: document retained Zim v2 demo roles`

## Verification

Focused logs are preserved at:

```text
.test-agent/config-contexts/build5-review0-verification/
```

All 15 checks passed:

| Area | Result |
|---|---|
| bin compositor filter | passed |
| config-context compiler filter | passed |
| Zim-context v2 compiler filter | passed |
| Zim fragment filter (81 assertions) | passed |
| config-context toolkit integration | passed |
| LINKS integration | passed |
| Mise integration | passed |
| deployment-orchestrator identity | passed |
| Zim donor integration | passed |
| Zim consumer/user/system/contributor integration | passed |
| strict native TypeScript (`tsgo`) | passed |
| Zim playbook syntax | passed |
| Zim TypeScript syntax | passed |
| config-toolkit TypeScript syntax | passed |
| shell-wrapper syntax | passed |

No full repository sweep was run.

## Retained demo

The current safe scratch proof is:

```text
/home/rektide/src/compfuzor/.test-agent/config-contexts/zim-demo-k960e_e3
```

Its README and wrappers cover the two users, explicit system activation,
relocated v2 loader sources, neutral contributor command, and hostile inherited
environment isolation. The host's `install-zim-system.sh` is a manually created
test symlink; the test first proves that the render contains no alias.

## Remaining limitations

- Loader projection is intentionally Zim-specific and fixed to `zimenv` and
  `zimrc`; it is not a core config/install/build facility or arbitrary channel
  map.
- A manually edited malformed v2 JSON shape may fail through the runtime's
  ordinary error path rather than a standalone JSON-schema validator. Compiler
  output and unsupported version are validated.
- Compfuzor does not prune artifacts from an older deployment; any future live
  migration must deliberately handle stale historical files.
- No live deployment has been attempted, and the full repository test sweep was
  outside this focused review.

The previously documented requirement for external `ZIM_*` values in a system
loader is no longer a limitation.

## Scope preservation

The pre-existing uncommitted `files/config-remote.ts`,
`library/filter_plugins/config_compile.py`, `jujutsu.src.pb`, and
`termctrl.src.pb` changes remain uncommitted and were excluded from these
commits. No unrelated history was rewritten or discarded.

## Cross-references

- [`build5.solx.md`](/.design/config-user-target/build5.solx.md) is the corrected
  implementation checkpoint.
- [`consumer-toolkit.md`](/doc/config/consumer-toolkit.md) is the current
  operator-facing declaration and workflow guide.
- [`zim_context_compile.py`](/library/filter_plugins/zim_context_compile.py)
  emits the bounded v2 contract.
- [`zim_consumer.test.py`](/tests/integration/zim_consumer.test.py) is the
  executable precedence, relocation, source, status, contributor, and no-alias
  proof.
