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
| `KERNEL_MODULES` | dict of kernel modules with optional params     |
| `KERNEL_SYSCTL`  | dict of sysctl key-value pairs                   |

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

## Generative subsystems (vars_*.tasks)

Generative subsystems are `vars_*.tasks` files that transform playbook declarations into pipeline artifacts (ETC_FILES, BINS, ENV_LIST, LINKS). They run in the VARIABLES phase and are the primary extension point for new subsystems.

### Kernel subsystem (vars_kernel.tasks)

Configures kernel modules, modprobe parameters, and sysctl via three dict variables:

#### KERNEL_MODULES

Dict keyed by module name. Each value is a dict with an optional `params` sub-dict:

```yaml
KERNEL_MODULES:
  zswap:
    params:
      enabled: Y
      compressor: lz4
      zpool: z3fold
      max_pool_percent: 20
      accept_threshold_percent: 90
      same_filled_pages_enabled: Y
      exclusive_loads: Y
  pcie_aspm:
    params:
      policy: powersupersave
  i2c_dev: {}
```

From this dict, vars_kernel generates:

| Output | Source | Destination |
|---|---|---|
| modules-load conf | Module names | `/etc/modules-load.d/{{NAME}}.conf` |
| modprobe conf | Modules with `params` | `/etc/modprobe.d/{{NAME}}.conf` |

#### KERNEL_SYSCTL

Flat dict of sysctl key-value pairs. Generates a sysctl drop-in:

```yaml
KERNEL_SYSCTL:
  vm.swappiness: 60
  vm.max_map_count: 1048576
```

| Output | Destination |
|---|---|
| sysctl conf | `/etc/sysctl.d/{{NAME}}.conf` |

#### Generated scripts

`vars_kernel.tasks` generates `build.sh` and `install.sh`:

- **`build.sh`** — Templates config files from `env.export` variables. Uses `block-in-file --envsubst` so files are data-driven: change the env, re-run build.sh, files update.
- **`install.sh`** — Symlinks generated files from the instance's `etc/` into system directories (`/etc/modules-load.d/`, `/etc/modprobe.d/`, `/etc/sysctl.d/`).

No systemd service is needed. The `install.sh` handles all deployment, and sysctl.d / modprobe.d / modules-load.d are read at boot.

#### ENV_LIST

`vars_kernel.tasks` populates `ENV_LIST` with all `KERNEL_MODULES` params and `KERNEL_SYSCTL` keys so the build.sh can interpolate them.

### Bypass flags

| Flag | Effect |
|---|---|
| `KERNEL_BYPASS: True` | Skip all kernel subsystem processing |

## The build/install pattern

A key architectural pattern for etc-type playbooks. Instead of writing static config files at playbook run time, the playbook declares data and the generative subsystem produces two scripts:

1. **`build.sh`** — Reads `env.export` (or environment variables), templates config files into `{{ETC}}/`. Idempotent. Re-run after changing env vars to regenerate config.
2. **`install.sh`** — Deploys generated files to system locations via symlinks. Idempotent.

This makes playbooks data-driven: the playbook sets defaults, the user can override via env vars, and `build.sh` regenerates to match.

### block-in-file and envsubst

`block-in-file` is compfuzor's managed-block injection tool. Beyond dotfile injection, it has key features for the build/install pattern:

- **`--envsubst`** — Passes content through `envsubst` before writing, replacing `${VAR}` references with environment variable values
- **`-n <name>`** — Named block for idempotent updates
- **`-o <file>`** — Target file to inject into
- **`--envsubst` with piped content** — `echo "$TEMPLATE" | block-in-file -n myblock -o /path/to/file --envsubst`

Example `build.sh` using envsubst:

```bash
cat "${DIR}/etc/zswap.conf.template" | block-in-file -n "${NAME}" -o "${DIR}/etc/zswap.conf" --envsubst
```

The template file contains `${ZSWAP_COMPRESSOR}`, `${ZSWAP_MAX_POOL_PERCENT}`, etc. These resolve from `env.export` at build time.

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
