# CompFuzor

Compfuzor is a convention-first deployment framework built on Ansible. A
playbook is usually a thin declarative card. The shared pipeline interprets the
card and turns it into files, directories, repositories, packages, services,
and helper scripts.

The filename is part of the spec.

## What It Is

Normal Ansible often pushes authors toward writing task logic over and over.
Compfuzor tries to move that repeated logic into shared machinery so that the
playbook mostly declares intent as variables. A good playbook often looks like:

```yaml
---
- hosts: all
  vars:
    <declarations>
  tasks:
    - import_tasks: tasks/compfuzor.includes
```

That single import is not a shortcut around work. It is the work: a shared
pipeline that resolves identity, layered vars, directories, files, env, repos,
packages, bins, and other subsystems.

## Why It Exists

Compfuzor is trying to solve a few things at once:

- stop rewriting the same operational Ansible tasks for every piece of software
- make deployments instanceable, so `main`, `test`, `git`, and other variants can coexist
- keep generated state inspectable in per-instance directories
- make installation rerunnable through generated scripts like `build.sh` and `install.sh`
- codify reusable operational patterns once, then expose them as declarative contracts

## Core Mental Model

- A playbook should declare data, not hand-roll repeated task logic.
- The shared pipeline in `tasks/compfuzor.includes` does the real work.
- Reusable patterns belong in `vars_*.tasks` generative subsystems.
- Deep structured inputs should live in machine-readable artifacts when that is the cleanest contract.
- Generated scripts in `bin/` should own imperative construction and deployment.

Compfuzor is not mainly a templating system. It is a system for generating
small operational programs from declarations.

## Anatomy Of A Playbook

Compfuzor playbooks are small, but they are not trivial. A good playbook is a
declaration of:

- identity, from the filename
- data artifacts to generate
- scripts the user will actually run
- optional package, repo, service, and filesystem requirements

The important thing to notice is that `BINS` is not an afterthought. `bin/` is
often the final operational surface the user gets: the workflows the playbook
creates.

### Example: A Featureful `opt` Playbook

```yaml
---
- hosts: all
  vars:
    PKGS:
      - jq

    ENV:
      APP_CHANNEL: stable
      APP_CONFIG_JSON: "{{ DIR }}/etc/app.json"

    ETC_FILES:
      - name: app.json
        json:
          channel: "${APP_CHANNEL}"
          cache_dir: "{{ DIR }}/var/cache"

    BINS:
      - name: build.sh
        src: ../example/build.sh
        basedir: False
      - name: install.sh
        src: ../example/install.sh
        basedir: False
        run: "{{ INSTALL_BYPASS is not deftruthy and BINS_RUN_BYPASS is not deftruthy }}"
      - name: open-config.sh
        content: |
          ${EDITOR:-vi} "$DIR/etc/app.json"
        basedir: False

  tasks:
    - import_tasks: tasks/compfuzor.includes
```

What is at stake in this example:

- `ETC_FILES` defines durable local data under the instance
- `ENV` publishes the shallow runtime contract
- `BINS` defines the actual workflows the instance exposes
- the playbook stays declarative even though the instance ends up operationally rich

## Filename As Spec

Playbooks are named `<NAME>.<TYPE>.pb`.

The filename drives identity:

- `TYPE` is the deployment category
- `NAME` is the instance name stem
- `INSTANCE` usually defaults to `main`, or `git` for some source-backed flows

Prefer letting the filename drive identity instead of restating everything in
vars.

## Instance Directory Model

Each playbook gets a primary directory. This is a sample shape, not a promise
that every instance will use every subdirectory:

```text
<DIR>/
  env
  env.export
  bin/
  etc/
  share/
```

In practice:

- `env` and `env.export` are the exported scalar runtime contract
- `bin/` is often the main user-facing operational surface
- `etc/` may hold structured data artifacts and rendered config outputs
- `share/` exists when the playbook needs shared assets, but is not universal

Generated scripts usually source `env.export`, but that is not the whole story:
structured artifacts in `etc/` often contribute just as much to runtime
behavior.

Typical type base directories:

| Type | System base | Usermode / XDG-ish base | Typical role |
|---|---|---|---|
| `etc` | `/etc/opt` | `$XDG_CONFIG_HOME` | configuration instances |
| `opt` | `/opt` | `$XDG_DATA_HOME/../opt` | optional software installs |
| `src` | `/usr/local/src` | `$HOME/src` | source checkouts and builds |
| `srv` | `/srv` | `$XDG_DATA_HOME/../srv` | service instances |

These base directories are not just path defaults. They are the spatial model
for how compfuzor thinks about software: configuration, source, services, and
installed software each have a different home and a different operational role.

Because instance is part of the path, multiple instances of the same software
can coexist on one machine.

## The Pipeline

`tasks/compfuzor.includes` runs in broad phases:

1. variables
2. user and become setup
3. repositories
4. filesystem
5. extras

Most design work happens in the variables phase. That is where base context is
resolved and where generative subsystems (`vars_*.tasks`) translate high-level
declarations into standard pipeline artifacts.

## How A Playbook Turns Into Work

Compfuzor has a few recurring design moves. This section is not just a list of
features; it is the grammar the system uses to turn declarations into an
operational instance.

### Hierarchy Variables

Prefer hierarchy-specific variables instead of dumping everything into generic
`FILES`.

- `ETC_FILES` for config payloads
- `SHARE_FILES` for shared assets
- `BINS` for executable helpers
- `ETC_DIRS`, `SHARE_DIRS`, and peers for hierarchy subdirectories

This keeps playbooks aligned with the instance directory model and makes the
resulting instance easier to inspect.

### `BINS` As Workflow Surface

`BINS` is a core part of the model. It is often the final user-facing interface
that a playbook creates.

Examples of what `BINS` can embody:

- `build.sh`
- `install.sh`
- `config.sh`
- service helpers
- repair or migration commands

Compfuzor is often generating workflows as much as files.

### ENV vs Deep Data

- `ENV` is for scalar key/value runtime contract data
- `ENV_LIST` names variables a subsystem wants exported
- `ETC_FILES` can carry deeper structured artifacts like JSON when that is a better contract than flattening into env vars

Use env for shallow knobs. Use data files for structured state.

### Build / Install

One of the most important compfuzor patterns:

- `build.sh` constructs canonical outputs from data
- `install.sh` deploys or applies those outputs

This separation gives you an inspectable and rerunnable workflow.

### File-Backed Generated Scripts

Large shell bodies should not live forever inline inside `vars_*.tasks`.
Prefer placing them under `files/<subsystem>/` and referencing them from `BINS`.

That keeps the task file focused on structure and lets the script files focus on
behavior.

### Ordered Domain Tables

When building a subsystem, prefer one ordered domain/spec table and derive
multiple outputs from it.

For example, a subsystem may derive from one table:

- `ETC_FILES`
- `ENV`
- `ENV_LIST`
- `BINS`
- aggregate build/install orchestration

This avoids parallel arrays, zip-style coupling, and duplicated selection logic.

### Generative Subsystems

`vars_*.tasks` files are where compfuzor grows new declarative languages.

They should:

- define contracts
- normalize data once
- derive standard artifacts
- keep imperative logic in generated scripts or file-backed helpers

That is the mechanism that lets many playbooks stay small.

## Target Requirements

- Debian-like target is generally assumed
- systemd is assumed as init system
- dpkg/apt is assumed for package management
- write access is typically needed for `/opt`, `/srv`, `/usr/local/src`, and related managed paths
- many playbook scripts use `block-in-file`, which currently expects node or deno to be available

## Repository Layout

- `/` contains playbooks
- `tasks/` contains task fragments used by playbooks
- `tasks/compfuzor/` contains the main compfuzor execution pipeline and subsystems
- `vars/` contains broad configuration data and defaults
- `files/` contains file-backed script and config assets used by playbooks and subsystems
- `private/` contains sensitive local configuration
- `example-private/` contains mock/example forms of corresponding private data
- `skill/` contains authoring guidance for working inside compfuzor

## Running And Iterating

The normal loop is:

1. declare intent in the playbook
2. run the playbook
3. inspect generated files under `DIR`
4. rerun `build.sh` or `install.sh` as needed

That rerunnable script model is deliberate. Generated scripts are not just
implementation details; they are user-facing operational tools.

## More Guidance

If you want to contribute or author new playbooks/subsystems, read
[`skill/SKILL.md`](/home/rektide/src/compfuzor/skill/SKILL.md). The README is
for orientation; the skill is the stronger authoring guide.

## Bypass And Skip Controls

<details>
<summary><strong>Bypass Variables</strong></summary>

CompFuzor provides several mechanisms to skip or reduce work when you do not
need to run all steps, or when running steps would stomp local work.

### Bypass Overview

Set any of these to `True` to skip that stage:

| Variable | What it bypasses |
|---|---|
| `APT_BYPASS` | apt repository configuration and package installation |
| `APT_UPDATE_BYPASS` | `apt update` work |
| `BINS_BYPASS` | creation of managed scripts in `bin/` |
| `BINS_RUN_BYPASS` | execution of scripts marked to run |
| `DEBCONF_BYPASS` | debconf pre-configuration |
| `DIR_BYPASS` | directory creation and hierarchy setup |
| `DBCONFIG_BYPASS` | database configuration work |
| `ENV_BYPASS` | environment file generation |
| `FS_BYPASS` | filesystem operations broadly |
| `FS_SRCS_BYPASS` | source file operations |
| `GET_URLS_BYPASS` | URL download work |
| `GIT_BYPASS` | git repository operations |
| `GLOBAL_BINS_BYPASS` | linking binaries into global paths |
| `LINKS_BYPASS` | symlink creation |
| `MODULES_BYPASS` | kernel module loading work |
| `PKGS_BYPASS` | package installation via apt |
| `REPO_BYPASS` | repository operations broadly |
| `SYSTEMD_BYPASS` | systemd service/unit generation and install |
| `SYSTEMD_THUNK_BYPASS` | legacy systemd thunk operations |
| `TGZ_BYPASS` | tarball extraction |
| `ZIP_BYPASS` | zip extraction |

All BYPASS variables default to `False`.

### Other Skip / Safety Controls

#### `APT_INSTALL`

Controls the state for apt package installations. Default is often `latest`,
but `present` can avoid unnecessary upgrades.

```yaml
APT_INSTALL: present
```

#### `GIT_UPDATE`

Controls whether git repositories are updated. Useful when local modifications
should be preserved.

```yaml
GIT_UPDATE: false
```

</details>

## Migration Guide

<details>
<summary><strong>Migration Guide</strong></summary>

Many playbooks predate current conventions. When touching one, prefer to move it
toward these patterns.

### `include:` To `import_tasks:`

```yaml
# old
- include: tasks/compfuzor.includes

# current
- import_tasks: tasks/compfuzor.includes
```

### Type In Filename, Not Task Parameters

```yaml
# old
- import_tasks: tasks/compfuzor.includes type=src

# current
# encode type in the filename, e.g. foo.src.pb
- import_tasks: tasks/compfuzor.includes
```

### Prefer Hierarchy Vars Over Generic Files

- move generic `FILES` toward `ETC_FILES`, `SHARE_FILES`, and peers
- move repeated shell bodies into `files/<subsystem>/`
- move repeated task logic into `vars_*.tasks`

### Staleness Signals

Watch for these:

- inline `BINS` content that has grown large and should be file-backed
- hard-coded absolute paths that should use `DIR`, `NAME`, or hierarchy vars
- repeated custom tasks across multiple playbooks
- feature logic living in playbooks when it should be a subsystem contract

</details>

## Glossary

<details>
<summary><strong>Glossary</strong></summary>

### `DIR`

The primary instance directory for a playbook.

### Hierarchy Prefixes

Common hierarchy roots include:

- `SRV`
- `OPT`
- `ETC`
- `VAR`
- `LOG`
- `SPOOL`
- `CACHE`
- `PID`
- `RUN`
- `SRC`
- `SHARE`

Examples:

- `SRV` for service instance directories, usually rooted at `/srv`
- `OPT` for optional software installs, usually rooted at `/opt`
- `ETC` for per-instance configuration payloads
- `SRC` for source checkouts, usually rooted at `/usr/local/src`

### `ENV` / `env.export`

The exported scalar runtime contract for generated scripts.

### `ETC_FILES`

Per-instance configuration and data artifacts. These may include rendered
configs, JSON contracts, or other structured inputs that generated scripts read.

### `BINS`

Managed scripts deployed into `<DIR>/bin/`, wrapped with the standard compfuzor
script header/footer.

### `vars_*.tasks`

Generative subsystems that translate declarations into standard compfuzor
artifacts.

</details>
