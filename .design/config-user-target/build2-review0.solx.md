---
type: ArchitectureCheckpoint
title: Consumer config toolkit review corrections
description: Correct compositor scope, reporter semantics, assembly diagnostics, path identity, glob selection, and type safety before any Zim migration.
resource: /.design/config-user-target/build2-review0.solx.md
tags: [compfuzor, config, links, status, zim, review]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
stale_after: 2026-10-08
sources:
  - id: accepted-checkpoint
    resource: /.design/config-user-target/build2.solx.md
    title: Consumer config donor and output toolkit
  - id: zim-channels
    resource: /.design/zim-generator/channels1.gpt56s.md
    title: Dual Zim startup channels
---

# Consumer config toolkit review corrections

## Outcome

The build2 architecture remains intact. This pass corrected its integration and
diagnostic boundaries without adding production consumers.

- A system context retains `context.scope: system`, but generated BINS omit a
  scope suffix. Its ordinary dispatcher now joins bare `install.sh`; user
  contexts still join `install-user.sh`.
- `status-config-context-<name>.sh` is a reporter adapter: raw toolkit source
  errors remain exit 2, while any non-clean reporter result becomes exit 1 so
  [`status.sh`](/files/status/status.sh) cannot silently treat it as
  not-applicable.
- Status emits separate `assembly` and `output` rows. A valid local regular
  assembly is healthy when the canonical aggregate is absent; the output row
  carries that absence as information. Whole-copy/link still fail without the
  canonical source. A healthy donor copy/link can likewise coexist with an
  assembly-readiness error when local inputs have not been activated.
- Assembly status now invokes the shared runner with `--stdout`, captures the
  byte-exact validated candidate, and compares it to the consumer output.
  Missing leaves, processor failures, validator failures, and read failures are
  evaluation errors with their stderr/cause—not invented content drift.
- CONFIGS status accepts symlinks whose final regular-file referent equals the
  donor, including relative targets, parent aliases, and links directly to the
  producer behind a donor symlink. LINKS ownership still uses its stricter
  literal managed target.
- Delivery now resolves each path's physical parent while leaving the final
  destination entry unresolved. `/donor/a` and `/alias-to-donor/a` are rejected
  as the same directory entry, preventing copy or self-link damage; replacing a
  final consumer symlink remains permitted.
- Runtime donor matching uses Node's filename glob matcher with a prefix that
  keeps leading-dot behavior compatible with `find -name`. Bracket patterns are
  supported. Shared assembly excludes configured disabled suffixes even when a
  broad pattern such as `*` would otherwise match them; donor catalog status
  still intentionally sees active and disabled entries.
- The new TypeScript was checked with the real native checker. It found and
  fixed overloaded `readdir` typing, an optional-suffix narrowing issue, and
  isolated-declaration parameter annotations.

## Verification

The rendered integration now additionally proves:

- bare `install.sh` contains the system context dispatcher and no
  `install-system.sh` is emitted;
- a generated aggregate status reports missing/dangling context sources as
  failure;
- local assembly remains healthy without a canonical output;
- whole-only output health and assembly readiness are distinct rows;
- alias, relative, producer-direct, and dangling link classification;
- alias-parent copy/link rejection without donor mutation and ordinary final
  symlink detachment;
- unavailable processor, validator failure, and unreadable comparison
  diagnostics;
- bracket patterns, leading-dot files, broad `*` disabled exclusion, and empty
  existing input directories.

Focused shared-delivery tests plus the existing LINKS suite report nine passes.
All config compiler, rendered config/context, config-remote, Zim-remote, LINKS
status/generation, Bash syntax, Node syntax, and Python compile checks pass.

The isolated typecheck lives under `.test-agent/config-contexts/typecheck/` and
uses only scratch dependencies:

```bash
pnpm add -D @typescript/native-preview@latest @types/node@latest
pnpm exec tsgo -p tsconfig.json
```

Its `tsconfig.json` uses `strict`, `noEmit`, `allowImportingTsExtensions`,
`isolatedDeclarations`, `declaration`, NodeNext modules, and Node types. No
project dependency manifest changed.

## Zim operational migration proposal

### Current coupling to remove

The current host and contributor lifecycle crosses the new ownership boundary:

- [`install-zim.sh`](/files/install-zim.sh) feeds producer fragments to the
  host's canonical `config-remote.ts`, mutating the shared `zimrc.d`/`zimenv.d`
  roster, then builds touched user channel caches.
- Contributor [`install-user-zimfw.sh`](/tasks/compfuzor/gen_zim.tasks) invokes
  that host-scoped mutation during an ordinary user install.
- The host [`install-user.sh`](/zim.opt.pb) self-promotes its own fragments,
  rebuilds canonical configs, inserts both loaders, and installs the registry
  link in one body.

That means “install for this user” can change globally shared input choices.
The migration should split donor administration, consumer contribution, local
assembly, loader installation, and cache activation.

### 1. Populate the host baseline during normal rendering

For `ZIM_HOST`, render the host's own `ZIM_MODULES` directly into canonical
CONFIGS input directories:

```text
ETC/zimrc.d/<phase-name>.conf
ETC/zimrc.d/<phase-name>.conf.disabled
ETC/zimenv.d/<phase-name>.conf
ETC/zimenv.d/<phase-name>.conf.disabled
```

This removes self-promotion through `install-zim.sh`. Filesystem generation
populates the donor catalog before any ordinary user installer can seed a
context. Canonical `config.sh` may still materialize donor aggregates for
administration, whole-output publication, and registry evidence, but it is not
part of consumer-local assembly.

Keep an explicitly named canonical/admin contribution tool for operators who
intend to change the shared donor roster. It may wrap today's
`config-remote.ts` behavior and rebuild canonical outputs, but it must not join
`install-user.sh` and must never build a user's Zim cache.

### 2. Bind both consumer channels locally

Use one context:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    install: assemble
    dropins: link
    configs:
      zimrc:
        output: {env: ZIM_CONFIG_FILE, default: zimrc}
      zimenv:
        output: {env: ZIM_ENV_CONFIG, default: zimenv}
```

The existing under-ETC bindings then naturally place inputs at
`$XDG_CONFIG_HOME/zsh/zimrc.d` and `zimenv.d`. Ordinary context install seeds
the host baseline as links and assembles both local outputs. Explicit copy,
link, refresh, disable, and local-addition workflows remain available.

`ZDOTDIR` continues to select `.zshenv` and `.zshrc`; it does not silently
replace the XDG config-root contract. Explicit `ZIM_CONFIG_FILE` and
`ZIM_ENV_CONFIG` continue to override each channel output.

### 3. Give producer installs a consumer-local route

Replace contributor calls to the canonical `install-zim.sh` with a host
`install-zim-context.sh <producer-dir>` operation. It discovers the host, maps
`etc/zim/<channel>/{active,disabled}` to the corresponding context input, and
uses `config-inputs-user.sh put` with link strategy. Disabled additions can use
the current put-then-disable sequence; a small `put --disabled` ergonomic
extension would avoid the transient active rebuild but is not an architectural
requirement.

This makes a newly installed producer available to the invoking user without
changing the baseline catalog for every consumer. Promotion into the shared
donor remains the separate admin action above.

After all fragments from one producer are installed, rebuild each touched local
channel and invoke its channel builder once. Do not build user caches from the
canonical admin path.

### 4. Keep activation and loader artifacts distinct

After local assembly, `zimfw-channel.sh` should build:

- `${ZIM_ENV_HOME:-$HOME/.cache/zim-env}/init.zsh` from the resolved local
  `${ZIM_ENV_CONFIG:-$XDG_CONFIG_HOME/zsh/zimenv}`;
- `${ZIM_HOME:-$HOME/.cache/zim}/init.zsh` from the resolved local
  `${ZIM_CONFIG_FILE:-$XDG_CONFIG_HOME/zsh/zimrc}`.

Install `.zshenv` and `.zshrc` loaders as two separately declared
block-in-file artifacts with their own status. Their embedded defaults must use
the same local paths while retaining the two environment overrides. The
channel-cache freshness reporter compares each cache against its local config,
not the canonical aggregate.

### 5. Preserve a canonical registry

`ZIM_CONFIG_LINK`/`zimfw.conf` remains host-discovery evidence and must always
point to the canonical host output, independent of the consumer's runtime
`ZIM_CONFIG_FILE`. Express it through LINKS as a structural user link. Host
discovery becomes:

1. explicit `ZIM_HOST_DIR`;
2. `ZIM_CONFIG_LINK` or its XDG default;
3. `/opt/zim-main` fallback.

The current contributor discovery preference for `ZIM_CONFIG_FILE` should be
removed; a copied or locally assembled runtime output cannot identify the host.

### Proposed ordinary user order

```text
install-config-user.sh          # seed baseline + assemble local zimenv/zimrc
install-zim-loaders-user.sh     # two independent managed blocks
zimfw-channel.sh zimenv install # local config -> local cache
zimfw-channel.sh zimrc install  # local config -> local cache
install-zim-registry-user.sh    # canonical host registry link
```

The composed user wrapper may orchestrate these leaves, but none may call the
canonical donor mutation tool implicitly.

## Mise assessment

[`mise.opt.pb`](/mise.opt.pb) already says Zsh activation belongs to Zim's
`zimenv` channel. Its remaining Bash integration consists of two independent
managed blocks (`.bashrc` and `.bash_profile`) plus a separate settings action.
Those are block-in-file artifact installation/status concerns, not a CONFIGS
assembly. The Zim migration should not manufacture a Mise input graph merely to
reuse this toolkit.

## Remaining review boundary

No Zim declarations, producer generators, loader blocks, registries, caches, or
Mise files changed in this checkpoint. The route above needs parent approval
before implementation, especially the direct-render host baseline and the
canonical-admin versus consumer-contribution command names.

## Cross-references

- [`build2.solx.md`](/.design/config-user-target/build2.solx.md) is the accepted
  toolkit checkpoint corrected here rather than rewritten.
- [`delivery.ts`](/files/links/delivery.ts) contains physical-entry protection
  and separate literal versus final-referent link comparison.
- [`config/toolkit.ts`](/files/config/toolkit.ts) contains captured assembly
  evaluation and separate status rows.
- [`config_context_toolkit.test.py`](/tests/integration/config_context_toolkit.test.py)
  is the rendered integration proof.
- [`channels1.gpt56s.md`](/.design/zim-generator/channels1.gpt56s.md) remains the
  two-channel behavioral basis; this proposal changes ownership and lifecycle,
  not the channel semantics.
