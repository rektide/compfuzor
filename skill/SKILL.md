# compfuzor

Compfuzor is a convention-based software deployment framework built on Ansible. The filename IS the spec.

Each `.pb` file is a thin declarative card declaring what to deploy. A single shared pipeline (`tasks/compfuzor.includes`) interprets all playbooks through a uniform process: parse identity from the filename, resolve layered variables, provision the filesystem, install packages, deploy configs, and link binaries. There is no per-software task logic in the pipeline — only variable declarations that drive shared machinery.

## The target directory

Every compfuzor playbook deploys to a single primary directory derived from three things: the **type** (from the filename), the **instance** (defaults to `main`, or `git` for source builds with a repo), and the **type's base directory**.

### Filename identity

Playbooks are named `<NAME>.<TYPE>.pb`. The filename is parsed at runtime to set:

- `TYPE` — the deployment category (src, etc, opt, srv, pkg, repo)
- `NAME` — defaults to `TYPE-INSTANCE` (e.g. `caddy-git`, `zsh-main`)
- `INSTANCE` — defaults to `main`, or `git` when `REPO` is defined and the cmdline instance is `src`

The playbook can override any of these with explicit vars, but convention is to let the filename drive.

### Default instance

When `INSTANCE` is not explicitly set in a playbook:

- If a `REPO` is defined and the playbook was invoked as `type=src`, INSTANCE defaults to `git`
- Otherwise INSTANCE defaults to `main`

This means `caddy.src.pb` with a `REPO` becomes `caddy-git` at `/usr/local/src/caddy-git`. An `etc` playbook like `zsh.etc.pb` becomes `zsh-main` at `/etc/opt/zsh-main`.

### Instance multiplicity

Because the instance is part of the directory name, you can coexist multiple deployments of the same software:

- `zsh.etc.pb` → `/etc/opt/zsh-main/`
- `zsh.etc.pb` with `INSTANCE: test` → `/etc/opt/zsh-test/`
- `caddy.src.pb` → `/usr/local/src/caddy-git/`

Each instance is a self-contained slot with its own env, bins, configs, and share data.

### Standard directory layout

Every instance directory has this shape:

```
<DIR>/
  env              # key=value metadata (DIR, NAME, TYPE, INSTANCE, etc.)
  env.export       # same, but with `export` prefix for shell sourcing
  bin/             # managed scripts with standardized headers/footers
  etc/             # symlink → <DIR> (for etc-type playbooks)
  share/           # symlink → /usr/local/share/<NAME>/
```

The `env` / `env.export` files are the instance's identity card. Scripts in `bin/` source `env.export` at startup to discover their own `DIR`, `NAME`, and other runtime variables.

### Type base directories

| Type    | Base Directory     | Example DIR                     | Purpose                            |
|---------|--------------------|----------------------------------|------------------------------------|
| `etc`   | `/etc/opt`         | `/etc/opt/zsh-main`             | System configuration instances     |
| `opt`   | `/opt`             | `/opt/ripgrep-main`             | Third-party software installs      |
| `src`   | `/usr/local/src`   | `/usr/local/src/caddy-git`      | Source checkouts & builds          |
| `srv`   | `/srv`             | `/srv/headscale-main`           | Services / daemons                 |
| `pkg`   | `/opt`             | `/opt/somepackage-main`         | Package-like installs              |
| `repo`  | `/opt`             | `/opt/myrepo-main`              | Repository mirrors                 |

### Hierarchy variables

For each type prefix in DIRSET (opt, srv, etc, var, log, spool, cache, src, pid, share), the pipeline looks for three variable patterns:

- `<PREFIX>_DIR` — override the directory for this hierarchy (e.g. `SHARE_DIR`)
- `<PREFIX>_DIRS` — list of subdirectories to create (e.g. `ETC_DIRS: [z.d, zfunc.d, bin]`)
- `<PREFIX>_FILES` — list of files to deploy into this hierarchy (e.g. `ETC_FILES`, `SHARE_FILES`)
- `<PREFIX>_D` — list of files to assemble from `.d` fragments

These are processed by `fs_hierarchy.tasks` which creates the directory, symlinks it into the instance dir, creates subdirs, deploys files, and assembles `.d` fragments.

### Usermode directories

When `USERMODE: True` is set, all directory bases relocate under the user's XDG directories:

| Standard Base    | Usermode Base                         |
|------------------|---------------------------------------|
| `/etc/opt`       | `$XDG_CONFIG_HOME`                    |
| `/opt`           | `$XDG_DATA_HOME/../opt`               |
| `/srv`           | `$XDG_DATA_HOME/../srv`               |
| `/usr/local/src` | `$HOME/src`                           |
| `/var/lib`       | `$XDG_DATA_HOME/../var/lib`           |
| `/var/cache`     | `$HOME/.cache`                        |
| `/usr/local/bin` | `$XDG_DATA_HOME/../bin`               |

This lets the same playbook structure work for system-wide or per-user deployments.

## The pipeline

Every playbook follows this shape:

```yaml
---
- hosts: all
  vars:
    <declarations>
  tasks:
    - import_tasks: tasks/compfuzor.includes
```

The `compfuzor.includes` pipeline runs in order:

1. **Variables** — base, type, user, env, filesystem, then extras (apt, systemd, rust, npm, etc.)
2. **User** — set ownership/become defaults
3. **Repositories** — git, hg, svn, go get checkouts
4. **Filesystem** — DIR creation, DIRS, FILES, env files, hierarchy (etc/opt/srv/...), links
5. **Extras** — packages, bins execution, make/cmake builds, systemd units, sysctl

## Playbook variable reference

Key variables a playbook typically sets:

| Variable       | Purpose                                          |
|----------------|--------------------------------------------------|
| `TYPE`         | Override the type inferred from filename          |
| `INSTANCE`     | Override instance name (default: `main` or `git`) |
| `PKGS`         | apt packages to install                           |
| `REPO`         | git repo URL to clone                             |
| `REPO_GO`      | go module URL to fetch                            |
| `DIRS`         | subdirectories to create under DIR                |
| `FILES`        | files to template from `files/<TYPE>/`            |
| `ETC_DIRS`     | subdirs for the `etc/` hierarchy                  |
| `ETC_FILES`    | files for the `etc/` hierarchy                    |
| `SHARE_DIRS`   | subdirs for the `share/` hierarchy                |
| `SHARE_FILES`  | files for the `share/` hierarchy                  |
| `BINS`         | scripts to deploy into `bin/`                     |
| `ENV`          | key-value pairs written to `env` / `env.export`   |
| `LINKS`        | symlinks to create (dict of dest→src)             |
| `GET_URLS`     | URLs to download                                  |
| `SYSTEMD_*`    | systemd unit generation vars                      |

## Managed scripts (BINS)

Scripts declared in `BINS` are deployed to `<DIR>/bin/` with a standard header/footer that:

1. Sets `TIMESTAMP`
2. Defaults `DIR` to the playbook's DIR
3. Sources `env.export` for runtime variable discovery
4. Pushes shell options onto a stack, enables `set -euo pipefail`
5. Runs the script body
6. Restores shell options from the stack

This means every managed script can rely on `DIR`, `NAME`, `TYPE`, `INSTANCE`, and any `ENV` vars being available.

The `basedir` field controls where the script runs. `basedir: False` means don't cd. `basedir: src/github.com/foo` means cd into the source tree. The `global: True` flag symlinks the script into `/usr/local/bin/`.

## File lookup convention

Templates in `FILES` and `<PREFIX>_FILES` are looked up from `files/<TYPE>/` by default. For string items (not dicts), the item name is both the source filename and the destination filename. Dict items can specify `name`, `src`, `dest`, `content` (inline template), `line` (lineinfile), `yaml`, `json`, or `var`.

## Block-in-file pattern

Compfuzor uses a `block-in-file` tool (similar to `blockinfile`) to inject managed blocks into user dotfiles. Each block has a name and is idempotent — re-running updates the block in place. This is how `install-user.sh` scripts inject sourcing into `~/.zshrc`, `~/.config/zsh/conf.d/*.conf`, etc. without overwriting existing content.

## Necessary migrations

Approximately half the playbooks in the repo predate current conventions. When you encounter any of these patterns, the playbook needs updating:

### `include:` → `import_tasks:`

```yaml
# OBSOLETE
tasks:
  - include: tasks/compfuzor.includes

# CORRECT
tasks:
  - import_tasks: tasks/compfuzor.includes
```

`include` is the old Ansible task keyword. `import_tasks` is the modern form. Every playbook using `include:` should be migrated.

### `type=` / `types=` parameter → filename encoding

```yaml
# OBSOLETE — type passed as parameter
tasks:
  - include: tasks/compfuzor.includes type=src

# OBSOLETE — same with import_tasks
tasks:
  - import_tasks: tasks/compfuzor.includes type=src

# CORRECT — type is encoded in the filename (e.g. caddy.src.pb)
tasks:
  - import_tasks: tasks/compfuzor.includes
```

The type should be part of the playbook filename (`<NAME>.<TYPE>.pb`), not a parameter. If the filename already has the type but the task still passes `type=`, remove the parameter.

### Other staleness signals

When editing a playbook, also watch for:

- Using `FILES` at the top level when the file belongs in a hierarchy (e.g. should be `ETC_FILES` or `SHARE_FILES`)
- Inline content in `BINS` that has grown complex enough to warrant a proper template file
- Hardcoded paths that should use `{{DIR}}` or `{{NAME}}` template variables

The convention is evolving. Prefer the patterns used in recently-edited playbooks over older ones.
