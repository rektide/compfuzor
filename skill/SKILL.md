# compfuzor

This document is for authoring and extending compfuzor.

Use the README for orientation. Use this skill for stronger guidance about how
to write a good playbook, how to build a good subsystem, and how to move older
code toward the preferred current style.

## Non-Negotiable Mental Model

- A playbook is a declarative card, not a bespoke task program.
- The shared pipeline in `tasks/compfuzor.includes` should do the heavy lifting.
- Reusable behavior belongs in `vars_*.tasks` generative subsystems.
- Deep structured inputs should stay structured when that makes the contract cleaner.
- Generated scripts should own imperative work.

If you find yourself writing lots of custom tasks in a playbook, stop and ask
whether you are really designing a subsystem.

## Filename Is Part Of The Contract

Playbooks are named `<NAME>.<TYPE>.pb`.

The filename drives:

- `TYPE`
- `NAME`
- default `INSTANCE`

Prefer letting the filename encode identity instead of restating it in vars or
task parameters.

## Instance Directory Model

Each playbook gets a primary `DIR` with a predictable structure:

```text
<DIR>/
  env
  env.export
  bin/
  etc/
  share/
```

Important consequences:

- the instance directory is an inspectable artifact, not a hidden implementation detail
- generated scripts should source `env.export`
- users should be able to rerun generated scripts safely
- multiple instances of the same software should usually be able to coexist

## Pipeline Shape

The standard playbook body is:

```yaml
---
- hosts: all
  vars:
    <declarations>
  tasks:
    - import_tasks: tasks/compfuzor.includes
```

`tasks/compfuzor.includes` runs broad phases:

1. variables
2. user/become setup
3. repositories
4. filesystem
5. extras

Most design work happens in the variables phase.

## Artifact Taxonomy

Choose the right artifact type for the shape of the problem.

### Hierarchy Files

Use hierarchy-specific variables instead of generic `FILES` whenever possible.

- `ETC_FILES` for config payloads
- `SHARE_FILES` for shared assets
- `BINS` for executable helpers
- `ETC_DIRS`, `SHARE_DIRS`, and similar for hierarchy subdirectories

### ENV vs ENV_LIST

- `ENV` is for concrete scalar key/value runtime contract data
- `ENV_LIST` names variables that should be exported

Do not flatten deep structured data into env just because env is convenient.

### `ENV: True`

Setting `ENV: True` populates `env.export` with standard variables (`NAME`,
`DIR`, and others) so generated scripts can use `$NAME` / `$DIR` shell variables
instead of baked-in Jinja templates like `{{NAME}}`.

Prefer `ENV: True` + shell variables in `BINS` scripts over Jinja expansion when
the script sources `env.export`. This keeps scripts rerunnable outside Ansible
and defers resolution to runtime.

### Deep Data Files

When the input is genuinely structured, prefer a machine-readable artifact in
`ETC_FILES` such as JSON or YAML.

Use `yaml:` or `json:` on the file entry instead of `content:` to let Ansible
render structured data natively (`to_nice_yaml` / `to_nice_json`). This avoids
formatting drift and keeps the config declarative.

```yaml
ETC_FILES:
  - name: config.yml
    yaml:
      telemetry: disabled
```

Use `content:` only when the file is truly a flat string or when you need
precise control over the output format.

Examples of structured file inputs:

- a domain table
- a map of modules to params
- a multi-part subsystem contract

The point is to preserve structure instead of smearing it across parallel vars.

## Data-First Generator Pattern

This is the core compfuzor design language for non-trivial subsystems.

### Preferred Shape

1. model the subsystem as ordered declarative data
2. derive standard artifacts from that data
3. keep big imperative logic in generated scripts, preferably file-backed
4. have aggregate `build.sh` / `install.sh` orchestrate narrower helpers

### Ordered Domain Tables

When a subsystem has multiple conceptual domains, prefer one ordered table of
domain specs and derive from it.

From one domain table, you can often derive:

- `ETC_FILES`
- `ENV`
- `ENV_LIST`
- `BINS`
- aggregate script orchestration

This is better than:

- parallel arrays that must stay in lockstep
- repeated `hasFoo`, `fooFiles`, `fooBins`, `fooEnv` branches everywhere
- zip-style coupling of related data

### Shape Data For Filters

If you want to use `map`, `selectattr`, or `items2dict`, shape the data model so
the transform is direct.

Good pattern:

- each domain carries an `etc_file`
- each domain carries a `build_bin`
- each domain carries an `install_bin`

Then assembly becomes simple and obvious.

## Build / Install Pattern

Generated scripts are first-class outputs.

### `build.sh`

`build.sh` should:

- read env/data artifacts
- construct canonical outputs under the instance directory
- be safe to rerun
- make the generated state easy to inspect before deployment

### `install.sh`

`install.sh` should:

- deploy or apply what `build.sh` produced
- be safe to rerun
- be the main user-facing operational entrypoint

### Aggregate Build / Install

When a subsystem has multiple narrower helpers, `build.sh` and `install.sh`
should usually orchestrate them rather than duplicating their logic.

## File-Backed Script Bodies

Large shell bodies should usually live under `files/<subsystem>/`, not inline in
`vars_*.tasks` forever.

Reasons:

- the task file stays focused on structure and data flow
- the shell is easier to read and test as shell
- the boundary between declarative assembly and imperative execution stays clear

Inline generated shell is acceptable when it is short and local. Large bodies
should move out.

## Authoring `vars_*.tasks`

### What A Good Subsystem Does

- defines a clean declarative contract
- computes derived values once
- derives many outputs from a small number of well-shaped vars
- keeps `set_fact` count low when practical
- emits standard artifacts the pipeline already knows how to consume
- keeps domain-specific detail near the implementation, especially in comments

### What A Good Subsystem Avoids

- repeated tiny `set_fact` stages for every output fragment
- one-off prose docs for specific features inside this skill
- hiding imperative deploy behavior directly in the vars phase
- parallel lists that have to be kept in sync by convention
- giant inline shell blobs when `files/<subsystem>/` would be clearer

### When To Create A Subsystem

Create or extend `vars_*.tasks` when:

- a pattern appears in more than one playbook, or clearly will
- the playbook is starting to encode a reusable domain contract
- the result can be expressed as standard compfuzor artifacts

Do not create a subsystem just because a single feature has many knobs.

## Authoring Playbooks

### Start With Existing Contracts

Try these first:

- `PKGS`
- `REPO`
- hierarchy vars like `ETC_FILES`, `SHARE_FILES`, `BINS`
- `ENV` / `ENV_LIST`
- existing subsystem vars such as `SYSTEMD_*`

### Prefer Declarations Over Custom Tasks

If a playbook is becoming mostly custom tasks, that is usually a sign the logic
should move into shared machinery.

### Keep Playbooks Thin

The playbook should usually be easy to scan in one screenful. Large logic bodies
belong in subsystems or file-backed scripts.

## Managed Scripts (`BINS`)

Scripts in `BINS` are wrapped by compfuzor's standard script header/footer.
They can assume:

- `DIR` is available
- `env.export` can be sourced
- shell safety flags are enabled
- `jq` is available on the host
- `block-in-file` is available on the host

Use this. Do not manually rebuild that runtime contract inside every script.

## `block-in-file`

`block-in-file` is one of the key compfuzor tools for managed file mutation.

Useful options:

- `-n <name>` for stable block identity
- `-o <file>` for the target file
- `--envsubst` for environment-based substitution before write

This is especially useful when `build.sh` is generating material from
`env.export`.

## Migration Guidance

When editing old playbooks, prefer to move them toward current conventions.

### Prefer `import_tasks:`

Use:

```yaml
- import_tasks: tasks/compfuzor.includes
```

not the old `include:` form.

### Put Type In The Filename

Prefer `foo.src.pb` over passing `type=src` into the include/import call.

### Move Generic Files Into Hierarchies

Prefer:

- `ETC_FILES`
- `SHARE_FILES`
- `BINS`

over broad top-level `FILES` where possible.

### Extract Repeated Logic

If two or three playbooks are doing the same shape of work, stop copying.
Design the contract and move the logic into a subsystem.

## Practical Smells

These usually mean the design wants work:

- a playbook with lots of hand-authored tasks
- a subsystem with many near-duplicate branches
- repeated `hasX` variables that could be replaced by one ordered data table
- outputs assembled by custom loops when `map`/`items2dict` would work if the data were shaped better
- env carrying data that really wants to stay structured

## What To Preserve When Rewriting Old Code

Even when modernizing, preserve these strengths:

- inspectable instance directories
- rerunnable generated scripts
- instance multiplicity
- convention-driven paths and identity
- operational clarity over abstraction for its own sake
