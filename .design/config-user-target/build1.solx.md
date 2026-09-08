---
type: ArchitectureCheckpoint
title: Reusable CONFIGS consumer binding
description: Working checkpoint for scope-neutral config assembly before donor delivery and Zim migration.
resource: /.design/config-user-target/build1.solx.md
tags: [compfuzor, config, consumer-context, assembly]
status: draft
generated: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
verified: { by: model:gpt56-sol-xhigh, at: 2026-09-08 }
stale_after: 2026-10-08
sources:
  - id: assessment
    resource: /.design/config-user-target/assessment0.unknown.md
    title: Reusable configuration tools, explicit consumer contexts
  - id: working-brief
    resource: /.design/config-user-target/build0.unknown.md
    title: Proposed consumer config toolkit
---

# Reusable CONFIGS consumer binding

## Checkpoint

One compiled deployment can now run the same CONFIGS recipe and processor leaves
against multiple explicit consumer roots. Context assembly is an overlay on the
canonical compiled spec, not a user-only assembly implementation.

The small ordinary declaration is:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: zsh
    configs: [zimrc, zimenv] # omit to expose every compiled config
```

At invocation time, `root: config` resolves to
`${XDG_CONFIG_HOME:-$HOME/.config}` for the invoking consumer. A system or test
consumer can instead use an exact root:

```yaml
CONFIG_CONTEXTS:
  system-test:
    scope: system
    root: /scratch/service-config
```

`scope` is explicit metadata. It does not select credentials or invoke sudo.
System contexts run with the caller's existing authority.

## Public and normalized interface

`root` accepts a scope-appropriate class or an exact selector. User classes are
`home`, `config`/`etc`, `state`/`var`, `cache`, `data`/`share`, `bin`, and `log`;
system classes omit `home`. Exact roots are absolute paths, known leading
HOME/XDG expressions, or `{env, default}` selectors. No shell evaluation occurs.

Paths already under the compiled `ETC` retain their relative layout under
`root/subpath`. A per-config mapping can override outputs and inputs:

```yaml
CONFIG_CONTEXTS:
  user:
    scope: user
    root: config
    subpath: example
    configs:
      app:
        output:
          env: APP_CONFIG_FILE
          default: outputs/app.conf
        inputs:
          0: inputs/base.conf       # numeric source-input index
          fragments: local/app.d   # unique compiled glob-input name
```

Relative selectors stay under the context base; absolute and HOME/XDG selectors
are exact. A compiled output or input outside `ETC` must have an explicit
context binding. The compiler intentionally rejects it rather than inventing an
`inputs/<config>/<index>` relocation.

The post-`config_compile` filter stores bindings like:

```json
{
  "contexts": {
    "user": {
      "scope": "user",
      "root": {"path": "${XDG_CONFIG_HOME}"},
      "subpath": "example",
      "configs": {
        "app": {
          "output": {"env": "APP_CONFIG_FILE", "default": {"relative": "outputs/app.conf"}},
          "inputs": [{"relative": "inputs/base.conf"}, {"relative": "local/app.d"}]
        }
      }
    }
  }
}
```

The context runtime resolves this into a private `0600` config spec, exports it
as `CONFIG_SPEC`, pins `DIR` to the runner's deployment rather than ambient
state, and executes the existing `config.sh`. `config-run.sh` and every existing
processor leaf read the selected spec. Processor, block policy, validation,
multi-output precommit, and commit behavior therefore remain one runtime.

Generated entry points are:

```text
bin/config-context.ts --context NAME [config.sh arguments]
bin/config-<context>.sh [--list | --check | --stdout] [CONFIG]
```

For the ordinary declaration above this is `bin/config-user.sh`. `--spec` and
`--runner` let the raw TypeScript source be exercised directly; deployed entry
points need neither. Canonical `bin/config.sh` still defaults to
`DIR/etc/config.spec.json` and its existing config selection behavior.

## Shared runtime hardening included in this slice

- Candidates for apply, check, and stdout are first built under the private
  transaction directory. Check/stdout do not require a writable output parent.
- After every selected candidate has been built and validated, changed apply
  candidates are staged beside their outputs and atomically committed.
- Staging files are registered for cleanup immediately.
- Existing regular-file modes are retained; new files and outputs detached from
  symlinks use `0600`.
- A selected output symlink is replaced as a directory entry even when its
  referent already has matching bytes. Assembly never commits through the link
  into the donor.
- Directories and special files are not replaceable outputs.

## Differences from build0

[`build0.unknown.md`](/.design/config-user-target/build0.unknown.md) mixed the
first assembly seam with proposed install/drop-in strategies. This checkpoint
deliberately narrows the schema:

- `root` replaces the more ambiguous context `dir`; it is either a named
  consumer root or an exact selector.
- `install`, `dropins`, target delivery, status classification, and strategy
  environment variables are not compiled yet.
- Context input bindings are first-class. Under-ETC paths map predictably;
  external paths require an explicit binding rather than a generated magic
  directory.
- The only generated context convenience command is assembly. There is no
  second config engine and no premature install dispatcher family.
- No LINKS implementation was copied or bypassed in this slice.

## Verification and resulting capability

Focused compiler tests cover context selection, class/exact roots, output env
selectors, named and indexed input overrides, external-path requirements, and
command collisions. A real Ansible-rendered integration covers:

- one deployment serving two independent HOME/XDG contexts and an exact system
  scratch context, including spaces in every root;
- concat, JSON deep merge, and block-in-file through the existing processor
  leaves;
- canonical `config.sh`, contextual list/check/stdout, named apply, and default
  apply;
- missing output parents during check/stdout, unchanged outputs, validation
  failure before any commit, local mode retention, new `0600` modes, symlink
  detachment, and a foreign ambient `DIR`;
- direct execution of both deployed and repository-source TypeScript under
  Node 26 type stripping.

This makes consumer-local assembly real and scope-neutral. It does **not** yet
seed or refresh donor inputs, classify copy/link/local/disabled input state,
publish whole donor outputs, or provide context-aware mutation commands. A
plain reassembly only consumes the current bound inputs, which is the intended
foundation for preserving local edits and disabled choices.

## Proposed next slice: donor drop-ins through LINKS

Use the working context binding as the destination authority and add one bounded
donor-input delivery slice:

1. Compile declared donor glob entries to the bound consumer input directory,
   retaining config/input identity and active versus disabled destination name.
2. Materialize **link** actions as records consumed by the existing LINKS
   runtime, selected by stable IDs. Do not add another `symlink()` path.
3. Correct LINKS auto-privilege routing so `scope: user` never escalates; system
   work remains an explicitly privileged invocation.
4. Add a small copy sibling over the same normalized relationships. Explicit
   copy/link refresh may replace regular files or symlinks, but must reject
   directories/special files and never follow a destination symlink.
5. Generate `install-config-<context>-dropins-{copy,link}.sh`, a default seeding
   entry point, and status that accepts matching copies and links, reports local
   extras and enabled/disabled state, and never prunes.
6. Keep `config-<context>.sh` assembly independent: it must not refresh inputs.
   Only default install seeds absent donor entries; explicit refresh updates
   declared entries while preserving disabled names.

Prove that generic path first against scratch contexts, then review the
interfaces before migrating either Zim channel or its separate loader blocks.

## Cross-references

- [`config_context_compile.py`](/library/filter_plugins/config_context_compile.py)
  is the pure binding compiler layered after the existing CONFIGS compiler.
- [`config-context.ts`](/files/config-context.ts) resolves runtime consumer paths
  and delegates to the shared runner.
- [`config-run.sh`](/files/config-run.sh) owns common validation and commit
  semantics; [`config-processor.sh`](/files/config-processor.sh) reads the same
  selected spec.
- [`config_contexts.test.py`](/tests/integration/config_contexts.test.py) is the
  rendered multi-consumer proof.
- [`links.ts`](/files/links/links.ts) remains the required link implementation
  seam for the proposed next slice.
