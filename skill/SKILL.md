# compfuzor

Compfuzor is a convention-first deployment framework built on Ansible. The
playbook is a small declarative card. The shared pipeline interprets that card
and turns it into files, scripts, links, packages, repos, and services.

The filename is part of the spec.

## Mental model

- A `.pb` file should declare data, not hand-roll task logic.
- The shared pipeline in `tasks/compfuzor.includes` does the real work.
- Repeated behavior belongs in `vars_*.tasks`, not copied across playbooks.
- Feature-specific details belong in code comments near the subsystem that owns
  them, not in this skill.

This document should help with two jobs:

1. authoring playbooks
2. authoring or extending generative subsystems (`vars_*.tasks`)

## Filename identity

Playbooks are named `<NAME>.<TYPE>.pb`.

The pipeline derives identity from that filename:

- `TYPE` is the deployment category
- `NAME` is the instance name stem
- `INSTANCE` defaults to `main`, or `git` for source-backed playbooks in some
  repo flows

Prefer letting the filename drive identity instead of re-stating it in vars.

## Directory model

Each playbook gets a primary instance directory:

```text
<DIR>/
  env
  env.export
  bin/
  etc/
  share/
```

`env` and `env.export` are the instance identity card. Generated scripts should
source `env.export` and treat those values as the canonical runtime inputs.

Common type bases:

| Type | Base directory |
|---|---|
| `etc` | `/etc/opt` |
| `opt` | `/opt` |
| `src` | `/usr/local/src` |
| `srv` | `/srv` |

When `USERMODE: True`, these relocate under XDG-oriented user directories.

## Pipeline shape

Every playbook should look like:

```yaml
---
- hosts: all
  vars:
    <declarations>
  tasks:
    - import_tasks: tasks/compfuzor.includes
```

`tasks/compfuzor.includes` runs in broad phases:

1. variables
2. user/become setup
3. repositories
4. filesystem
5. extras

The variables phase is where most compfuzor design happens.

## Authoring playbooks

### Prefer declarations over tasks

Start with data the pipeline already knows how to consume:

- `PKGS`
- `REPO`
- `DIRS`
- `ETC_FILES`
- `SHARE_FILES`
- `BINS`
- `ENV` / `ENV_LIST`
- `LINKS`
- `SYSTEMD_*`

If a playbook mostly consists of custom tasks, that is usually a sign the logic
should move into a subsystem.

### Choose the right hierarchy

Use hierarchy-specific variables instead of dumping everything into top-level
`FILES`.

- config files: `ETC_FILES`
- shared assets: `SHARE_FILES`
- executable helpers: `BINS`

This keeps the playbook aligned with the instance directory model.

### Use build/install for generated config

When config should be rebuildable from data, do not hard-code the final `/etc`
payload directly in Ansible tasks. Generate helper scripts instead:

- `build.sh` renders static files into the instance `etc/`
- `install.sh` deploys them into system locations

That pattern lets users change env values, rerun `build.sh`, inspect the
rendered output, then rerun `install.sh`.

### ENV vs ENV_LIST

- `ENV` is for concrete key/value data to write into `env` and `env.export`
- `ENV_LIST` is for naming the keys a subsystem wants exported

If a generated script needs a value later, make that value part of the env
contract.

## Generative subsystems

`vars_*.tasks` files are compfuzor's main extension mechanism.

Their job is to take higher-level declarations and turn them into standard
pipeline artifacts:

- `ETC_FILES`
- `BINS`
- `ENV_LIST`
- `LINKS`
- other pipeline vars that existing phases already know how to consume

Think of them as generators or subsystem adapters, not feature docs.

### When to create a subsystem

Move logic into a `vars_*.tasks` file when all of these are true:

- the pattern appears in more than one playbook, or clearly will
- the playbook is starting to describe a reusable domain contract
- the output can be expressed as standard pipeline artifacts

Do not create a subsystem just because one feature has a lot of knobs.

### What a subsystem should do

- define a clean input contract
- compute derived values once
- batch output generation in as few `set_fact` actions as practical
- emit standard artifacts instead of performing deployment directly
- document subsystem-specific details in code comments near the implementation

### What a subsystem should avoid

- scattered `set_fact` calls for each tiny output
- baking one-off feature prose into `SKILL.md`
- hiding imperative deploy behavior inside the vars phase
- forcing playbooks to manually zip or correlate parallel lists of related data

If two values are semantically one object, model them as one object in the
contract.

## Build/install pattern

This is one of the core compfuzor patterns.

The vars phase generates scripts. Those scripts own the imperative work.

### `build.sh`

- reads `env.export`
- renders canonical files into the instance directory
- should be safe and repeatable
- should make it easy to inspect generated output before installation

### `install.sh`

- performs the privileged deployment step
- usually symlinks or injects generated files into their real system locations
- should also be safe and repeatable

The point is to separate declaration, rendering, and deployment.

## `block-in-file`

`block-in-file` is a key compfuzor tool for idempotent file management.

Useful options:

- `-n <name>` gives the managed block a stable identity
- `-o <file>` selects the output file
- `--envsubst` expands `${VAR}` placeholders from the environment before write

That `--envsubst` mode is especially important for generated config. A common
pattern is:

```bash
cat "${DIR}/etc/template.conf" | block-in-file -n "${NAME}" -o "${DIR}/etc/output.conf" --envsubst
```

This lets `build.sh` treat `env.export` as the source of truth for regeneration.

## Managed scripts

Scripts in `BINS` are wrapped by compfuzor's standard header/footer. They can
assume:

- `DIR` is available
- `env.export` can be sourced
- standard shell safety flags are applied

Prefer using generated scripts for behavior the user may want to rerun later.

## Migrations and staleness

Many older playbooks predate the current conventions. When touching one, prefer
to move it toward these patterns:

- `include:` to `import_tasks:`
- filename-driven type selection instead of `type=` arguments
- hierarchy vars instead of top-level `FILES`
- subsystem contracts instead of repeated custom task blocks

When in doubt, prefer the patterns used by recently-maintained playbooks and the
generative style used by active `vars_*.tasks`.
