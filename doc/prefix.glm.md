# Prefix Reference

This document maps compfuzor's prefix conventions to real task files. It is
grounded in what exists today and what the architecture draft describes as the
target direction.

The two source documents this synthesizes:

- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — facet catalog and phase vocabulary
- [`doc/pipeline-and-intent-prefix-memo.md`](pipeline-and-intent-prefix-memo.md) —
  full intent prefix table and authoring flow

## Two Axes

Compfuzor has two independent axes for any entity:

- **Phase**: when it runs in the pipeline (position in `.includes`)
- **Kind**: what family of work it represents (file prefix)

Do not conflate them. Phase is when. Kind is what.

## Pipeline Phases

The pipeline is [`tasks/compfuzor.includes`](../tasks/compfuzor.includes). Each
block of imports maps to a phase:

| Phase | Includes block | Kinds active |
|---|---|---|
| `compile` | `vars_base` through `vars_kernel` | `vars`, `probe` (future), `fn` (future), `syn` (future) |
| `user-context` | `user.tasks` | cross-cutting |
| `repo-apply` | `repo_*` imports | `repo` |
| `fs-apply` | `fs_*`, `bins*`, `links*`, `fs_d` imports | `fs`, `bins`, `links` |
| `extras-apply` | `apt`, `pkgs`, `pg`, `sysctl`, etc. | domain-specific execution |
| `post-run` | delayed `bins_link`, `systemd.thunk` | `bins` (delayed), `systemd` |

Current state: `compile` is entirely `vars_*` files today. The architecture
envisions splitting this into foundation (`vars`), discovery (`probe`),
transforms (`fn`), and synthesis (`gen`/`syn`).

## File Prefix Kinds

### `vars_` — Foundation

Sets base facts and defaults. Pure `set_fact`. No host mutations.

- Phase: `compile`
- Effect: `none`
- Output: normalized base facts consumed by downstream phases

Specimens:
- [`vars_base.tasks`](../tasks/compfuzor/vars_base.tasks) — core identity resolution
- [`vars_fs.tasks`](../tasks/compfuzor/vars_fs.tasks) — initializes temporary fs scratch facts
- [`vars_user.tasks`](../tasks/compfuzor/vars_user.tasks) — user/group resolution
- [`vars_env.tasks`](../tasks/compfuzor/vars_env.tasks) — env variable setup
- [`vars_src.tasks`](../tasks/compfuzor/vars_src.tasks) — source directory conventions

Convention: `vars_<domain>.tasks` prepares facts for a domain. Many domains
produce a companion `fs_<domain>.tasks` or `repo_<domain>.tasks` that applies
them.

### `fs_` — Filesystem Execution

Creates directories, files, downloads, env files. Mutates the host filesystem.

- Phase: `fs-apply`
- Effect: `host.fs`
- Output: files, directories, downloaded artifacts on disk

Specimens:
- [`fs_base.tasks`](../tasks/compfuzor/fs_base.tasks) — creates `DIR`, `DIRS`, `FILES`
- [`fs_get_urls.tasks`](../tasks/compfuzor/fs_get_urls.tasks) — downloads `GET_URLS` via `get_url`
- [`fs_env.tasks`](../tasks/compfuzor/fs_env.tasks) — writes `env`/`env.export` files
- [`fs_tgz.tasks`](../tasks/compfuzor/fs_tgz.tasks) — extracts tarballs
- [`fs_repo.tasks`](../tasks/compfuzor/fs_repo.tasks) — repo-related filesystem setup

### `repo_` — Repository Execution

Checks out and updates version control repositories. Mutates the host
filesystem.

- Phase: `repo-apply`
- Effect: `host.repo`
- Output: checked-out/updated repository directories

Specimens:
- [`repo_git.tasks`](../tasks/compfuzor/repo_git.tasks) — git clone/fetch
- [`repo_go.tasks`](../tasks/compfuzor/repo_go.tasks) — go get
- [`repo_cvs.tasks`](../tasks/compfuzor/repo_cvs.tasks), [`repo_svn.tasks`](../tasks/compfuzor/repo_svn.tasks), [`repo_hg.tasks`](../tasks/compfuzor/repo_hg.tasks)

### `bins` / `bins_*` — Script Execution

Creates and manages generated scripts. Mutates the host filesystem.

- Phase: `fs-apply` (primary), `post-run` (delayed link passes)
- Effect: `host.fs`
- Output: scripts in `bin/`, symlinks in global bin dirs

Specimens:
- [`bins.tasks`](../tasks/compfuzor/bins.tasks) — creates `BINS_DIR` and writes bin scripts
- [`bins_link.tasks`](../tasks/compfuzor/bins_link.tasks) — symlinks bins into PATH
- [`bins_link_global.tasks`](../tasks/compfuzor/bins_link_global.tasks) — global bin links
- [`bins_run.tasks`](../tasks/compfuzor/bins_run.tasks) — runs bins marked with `run: true`

### `links` — Symlink Execution

Creates symlinks. Mutates the host filesystem.

- Phase: `fs-apply`
- Effect: `host.fs`
- Output: symlinks

Specimen:
- [`links.tasks`](../tasks/compfuzor/links.tasks)

### `_` (underscore) — Internal / Orchestrator

Control flow helpers and fanout machinery. Not a domain prefix. Mixed effects.

- Phase: cross-cutting
- Effect: `mixed`

Specimens:
- [`_multi.tasks`](../tasks/compfuzor/_multi.tasks) — fanout include for hierarchy tasks
- `systemd.thunk.tasks` — post-run systemd unit execution

## Domain Pairs

A key structural pattern: many domains have a `vars_<domain>` that prepares
data and an execution file that applies it. These pairs share a domain but
operate in different phases.

### `get_urls` Pair

| File | Kind | Phase | Effect | What it does |
|---|---|---|---|---|
| [`vars_get_urls.tasks`](../tasks/compfuzor/vars_get_urls.tasks) | `vars` | `compile` | none | Registers `get-urls.sh` as a `BINS` entry for re-downloading |
| [`fs_get_urls.tasks`](../tasks/compfuzor/fs_get_urls.tasks) | `fs` | `fs-apply` | host.fs | Downloads each URL, writes `.url` sidecar files |

Data flow: `GET_URLS` list → `vars_get_urls` registers refresh script → `fs_get_urls` performs initial download → `.url` files enable later refresh via `get-urls.sh`.

### `repo` Pair

| File | Kind | Phase | Effect | What it does |
|---|---|---|---|---|
| [`vars_repo.tasks`](../tasks/compfuzor/vars_repo.tasks) | `vars` | `compile` | none | Sets `*_DIR` facts for each repo in `REPOS`, adds `REPO_DIR`/`GOPATH` to `ENV` |
| [`repo_git.tasks`](../tasks/compfuzor/repo_git.tasks) | `repo` | `repo-apply` | host.repo | Clones/fetches git repositories |

Data flow: `REPO`/`REPOS` → `vars_repo` derives directory facts and env → `repo_git` performs checkout.

### `fs` Pair

| File | Kind | Phase | Effect | What it does |
|---|---|---|---|---|
| [`vars_fs.tasks`](../tasks/compfuzor/vars_fs.tasks) | `vars` | `compile` | none | Initializes scratch variables for fs subsystem |
| [`fs_base.tasks`](../tasks/compfuzor/fs_base.tasks) | `fs` | `fs-apply` | host.fs | Creates `DIR`, `DIRS`, renders `FILES` |

Data flow: `vars_fs` sets empty scratch → downstream `vars_*` populate `DIR`, `DIRS`, `FILES` → `fs_base` materializes them.

### `systemd` Cluster

| File | Kind | Phase | Effect | What it does |
|---|---|---|---|---|
| [`vars_systemd.tasks`](../tasks/compfuzor/vars_systemd.tasks) | `vars` | `compile` | none | Resolves systemd unit defaults |
| [`vars_systemd_unit.tasks`](../tasks/compfuzor/vars_systemd_unit.tasks) | `vars` | `compile` | none | Generates unit file content |
| `systemd.thunk.tasks` | internal | `post-run` | host | Enable/start systemd units |

See [`doc/user-service.glm.md`](user-service.glm.md) for the full systemd
patterning.

## Data Prefixes

These are fact-name conventions for values that flow through the pipeline. They
are not file prefixes. They describe the role of data held in Ansible facts.

| Prefix | Class | Form | Example | Description |
|---|---|---|---|---|
| `raw_` | input | prefix | `raw_urls` | unnormalized input values |
| `norm_` | normalization | prefix | `norm_urls` | validated/normalized values |
| `spec_` | model | prefix | `spec_urls` | ordered domain table |
| `drv_` | derivation | prefix | `drv_targets` | intermediate computed values |
| `out_` | output | prefix | `out_config` | completed transform payload |
| `merge_` | synthesis-input | prefix | `merge_bins` | merge-ready payload |
| `syn_` | synthesis-output | prefix | `syn_bins` | synthesized payload ready for pipeline merge |
| `_tmp_` | scratch | internal | `_tmp_count` | short-lived local values |

Envelope patterns carry data across task-file boundaries:

| Envelope | Kind | Example | Description |
|---|---|---|---|
| `_probe_<domain>` | probe | `_probe_fs` | probe handoff record |
| `_fn_<domain>_out` | fn | `_fn_config_out` | transform handoff record |
| `_syn_<domain>` | syn | `_syn_bins` | synthesis handoff record |

Data prefixes are primary semantics. Envelope naming is a transport shape.

## Future Kinds (Not Yet In Tree)

These are from the architecture draft. They do not have files yet but describe
where new work should go.

| Prefix | Kind | Class | Effect | Purpose |
|---|---|---|---|---|
| `gen_` | syn | synthesis | none | Artifact generation / merge. Replaces overloaded `vars_*` that do generative work. |
| `probe_` | probe | discovery | none | Host probing / snapshot. Produces `_probe_<domain>` envelopes. |
| `fn_` | fn | transform | none | Reusable transforms with declared input schemas. Produces `_fn_<domain>_out`. |

### `gen_` Migration Path

Some current `vars_*` files do generative work beyond setting defaults. The
architecture envisions migrating those to `gen_*`:

- `vars_get_urls.tasks` registers a generated bin script → future `gen_get_urls.tasks`
- `vars_systemd.tasks`/`vars_systemd_unit.tasks` generate unit content → future `gen_systemd.tasks`

`gen_` does not change execution semantics. It makes intent explicit: this file
synthesizes artifacts, it does not just normalize input.

## Authoring Checklist

When adding a new domain:

1. Does it need host-side effects? If no, `vars_<domain>.tasks` only.
2. Does it prepare data that an execution file consumes? Create a pair:
   `vars_<domain>.tasks` + (`fs_<domain>.tasks` or `repo_<domain>.tasks`).
3. Does it generate complex artifacts from multiple inputs? Consider `gen_<domain>.tasks`
   instead of overloading `vars_`.
4. Name facts with the appropriate data prefix (`raw_`, `norm_`, `spec_`, `syn_`).
5. Gate execution with a `<DOMAIN>_BYPASS` variable. This is the existing convention.
