# Configuration deployment log

## 2026-09-13

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
