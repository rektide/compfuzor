# Configuration deployment log

## 2026-09-13

### Vite+ packaged runtime cutover

Built the four controller-side deployment inputs with `pnpm build` (Vite+
`vp pack`) and rerendered Zim with the same local, no-package/no-repository
command used below. The render completed with `changed=5`, `failed=0`; it did
not invoke pnpm, npm, apt, downloads, or repository work. The new live runtime
is:

```text
/opt/zim-main/bin/config/command.mjs
/opt/zim-main/bin/config-remote.mjs
/opt/zim-main/bin/links/links.mjs
/opt/zim-main/bin/links.mjs -> /opt/zim-main/bin/links/links.mjs
/opt/zim-main/bin/zim/install.mjs
```

All four files are executable and byte-for-byte match their checked-in
`build/runtime` inputs. The six fixed CONFIG action names now link to
`config/command.mjs`. No Python file is present under `/opt/zim-main/bin`;
Python filter/lookup plugins remained on the Ansible controller.

An initial direct `install-zim.sh` run exposed a package-bootstrap side effect:
`pnpm init` had added a pnpm-only `devEngines.packageManager` constraint, while
the existing block helper invokes npm. npm rejected that constraint and the Zim
installer exited 2 while replacing startup blocks. The generated constraint
was removed with `pnpm pkg delete devEngines`; a clean Vite+ rebuild and a second
`install-zim.sh` run completed and restored both loaders and caches.

Final live checks all exited 0: `config-assemble.sh --check`,
`config-status.sh`, a temporary `config-user-status.sh` symlink (proving manual
`$0` alias inference), `links.mjs status --scope user -q`, `status-zim.sh`, and
aggregate `status.sh`. Both direct and aliased CONFIG status returned 72 rows;
`config-remote.mjs list` returned the two Zim remote targets. Zim cache, loader,
and registry status were all `ok`.

Mise was also rerendered because LINKS is shared. It completed with `changed=0`,
`failed=0`: that deployment does not currently materialize the LINKS manager.
Direct Mise Bash status and aggregate status both exited 0, and its bin tree
contains no `.ts` or `.py` files.

Compfuzor does not prune, so these pre-cutover TypeScript files remain as inert
live residue even though no current wrapper or fixed action points to them:

```text
/opt/zim-main/bin/config-remote.ts
/opt/zim-main/bin/config/{assembly,cli,command,context,file-state,input-state,inputs,install,invocation,publication,report,status}.ts
/opt/zim-main/bin/links.ts
/opt/zim-main/bin/links/{cli,delivery,links,manifest,operations}.ts
/opt/zim-main/bin/zim/{activation,cli,install}.ts
```

Focused verification covered a clean Vite+ build (including output-directory
cleaning), Vite+ format/lint/type checking, CONFIG command/context/remote and
transaction tests, LINKS delivery/manager/v1/v2/systemd tests, Zim
consumer/donor/demo tests, MCP remote integration, Mise blocks, BINS
composition, and Zim/Mise syntax checks. Vite+ reported four pre-existing
unused-import warnings and no errors.

Deployed the fixed CONFIG command runtime and Zim v2 adapter to `zim-main`, then
materialized Mise's maintained Bash activation blocks. The invoking user was
`rektide`; no system context or donor-admin command was used.

### Preconditions and rendering

`sudo -n true` exited 1, so no sudo path was used. `/opt/zim-main`,
`/etc/opt/zim-main`, `/opt/mise-main`, and `/etc/opt/mise-main` were already
writable by the invoking user. Both playbooks passed syntax checks:

```bash
ansible-playbook zim.opt.pb --syntax-check
ansible-playbook mise.opt.pb --syntax-check
```

The live renders used the required local connector and suppressed package,
repository, download, and automatic bin execution work while retaining
filesystem, config, and bin materialization:

```bash
ansible-playbook -i 'localhost,' -c local zim.opt.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True \
  -e REPO_BYPASS=True -e GIT_BYPASS=True \
  -e GET_URLS_BYPASS=True -e BINS_RUN_BYPASS=True

ansible-playbook -i 'localhost,' -c local mise.opt.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True \
  -e REPO_BYPASS=True -e GIT_BYPASS=True \
  -e GET_URLS_BYPASS=True -e BINS_RUN_BYPASS=True
```

Zim completed with `failed=0` (`changed=7`); Mise completed with `failed=0`
(`changed=3`). No apt, download, repository, or systemd thunk ran.

### Zim activation

`/opt/zim-main/bin/install.sh --help` reported the ordered children
`install-apt.sh` and `install-zim.sh`. The ordinary aggregate install was then
run with only its unrelated package lane bypassed:

```bash
COMPFUZOR_APTLANE_BYPASS=1 /opt/zim-main/bin/install.sh
```

It seeded 68 consumer input links, assembled `zimrc` and `zimenv`, installed the
isolated `zim-main-zimrc` and `zim-main-zimenv` startup blocks, built both
caches, and linked the registry. Existing startup content remained around the
managed blocks.

Post-install checks:

| Command | Exit/result |
|---|---|
| `/opt/zim-main/bin/config-assemble.sh --check` | 0 |
| `/opt/zim-main/bin/config-assemble.sh --list` | `zimenv`, `zimrc` |
| `/opt/zim-main/bin/config-assemble.sh --stdout zimenv` | 0; 316 bytes; SHA-256 `ced5560b6a084dfcb3db20d474394aa12631fe761261508f63f244a2a0c2a08a` |
| `/opt/zim-main/bin/config-status.sh` | 0 |
| `/opt/zim-main/bin/status-zim.sh` | 0; both loaders and caches `ok` |
| `/opt/zim-main/bin/status.sh` | 0 |

The JSON CONFIG status contained 72 rows: 2 `ready`, 70 `ok`; representations
were 2 assembly outputs and 68 input links. Physical examples:

```text
file  /home/rektide/.config/zsh/zimrc
file  /home/rektide/.config/zsh/zimenv
link  /home/rektide/.config/zsh/zimfw.conf -> /etc/opt/zim-main/zimrc
link  /home/rektide/.config/zsh/zimrc.d/20-environment.conf -> /etc/opt/zim-main/zimrc.d/20-environment.conf
link  /home/rektide/.config/zsh/zimenv.d/20-zim-mise.conf -> /etc/opt/zim-main/zimenv.d/20-zim-mise.conf
```

All six fixed CONFIG files are symlinks to
`/opt/zim-main/bin/config/command.ts`. Both config and Zim specs are version 2,
default to `user`, and expose the declared `canonical,user` and `user` context
sets respectively.

Two concurrent immediate post-install probes transiently observed command
lookup failures (`readlink` missing and `/usr/bin/env` reporting `node: Not a
directory`) while new shells initialized the just-built Zim/Mise environment.
A clean-shell trace showed a valid PATH, ten consecutive fixed-command launches
succeeded, and the final sequential status checks above remained clean. No
persistent drift or malformed activation file was found.

### Mise activation

`/opt/mise-main/bin/install-user.sh --help` reported only
`install-bash-user.sh`; no systemd child was composed. Running:

```bash
/opt/mise-main/bin/install-user.sh
```

applied the `mise-main` managed blocks to `/home/rektide/.bashrc` and
`/home/rektide/.bash_profile` and retained surrounding text. Both direct
`status-mise-bash.sh` and aggregate `status.sh` exited 0. The disabled systemd
environment bridge was not re-enabled or invoked.

### Deliberately retained migration residue

Compfuzor does not prune. These observed legacy files remain for deliberate
operator cleanup rather than automatic deletion:

```text
/opt/zim-main/bin/config.sh
/opt/zim-main/bin/config-processor.sh
/opt/zim-main/bin/config-toggle.sh
/opt/zim-main/bin/config-zimenv.sh
/opt/zim-main/bin/config-zimrc.sh
/opt/zim-main/bin/status-config.sh
/opt/zim-main/bin/status-config-zimenv.sh
/opt/zim-main/bin/status-config-zimrc.sh
/opt/zim-main/bin/disable.sh
/opt/zim-main/bin/enable.sh
/opt/zim-main/bin/install-user.sh
/opt/zim-main/bin/zimfw-channel.sh
/opt/zim-main/bin/processors/{block-in-file,concat,json-deep-merge}
/opt/mise-main/bin/install-bash.user.sh
/opt/mise-main/bin/install.user.sh
/opt/mise-main/bin/install-service-mise-user-env-user.sh
/opt/mise-main/bin/install-systemd-user.sh
/opt/mise-main/bin/install-unit.sh
/etc/opt/mise-main/mise-user-env.service
```

The Mise service/unit artifacts are residue only: the current compositor does
not reference them. This deployment made no prune or removal decision.
