# compfuzor — running playbooks locally

Compfuzor playbooks are Ansible playbooks (`.pb`); each generates a subsystem's
config/scripts under a type-derived dir, then optionally installs them.

## Invoking locally

Playbooks are `- hosts: all` and SSH to `localhost` without an inventory. Always
use the **local connector**:

```
ansible-playbook -i 'localhost,' -c local <name>.pb
```

Syntax-check (no connector needed):

```
ansible-playbook <name>.pb --syntax-check
```

## Bypass flags

Subsystems that need `become` (apt, `/etc/modules-load.d`, linking into
`/etc/systemd/system`, …) require passwordless sudo (`sudo -n true`). Skip any
subsystem with `-e <NAME>_BYPASS=True`:

| Flag | Skips |
|---|---|
| `PKGS_BYPASS` / `APT_BYPASS` | apt package install / apt repo config |
| `MODULES_BYPASS` | `/etc/modules-load.d` kernel module loading |
| `SYSTEMD_INSTALL_BYPASS` | systemd unit-file + install-script generation |
| `SYSTEMD_THUNK_BYPASS` | systemd enable/restart |
| `BINS_BYPASS` / `BINS_RUN_BYPASS` | bin generation / running bins |
| `DIR_BYPASS` / `FS_BYPASS` | directory + file creation |
| `LINKS_BYPASS` | symlinks into system dirs |
| `REPO_BYPASS` / `GIT_BYPASS` | source checkout |
| `ENV_BYPASS` | env file emission |
| `USERMODE=True` | user scope (`~/.config`, user systemd, no sudo) |

Iterate without side effects:

```
ansible-playbook -i 'localhost,' -c local <name>.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True -e MODULES_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True
```

## Where output lands

`DIR` = `{{<TYPE>S_DIR}}/{{NAME}}`, set by `vars/types/<type>.yaml` (bases in
`vars/common.yaml`). `NAME` defaults to `TYPE[-INSTANCE][-SUBINSTANCE]`.

| Suffix | Base dir |
|---|---|
| `.src.pb` | `/usr/local/src` (SRCS_DIR) |
| `.opt.pb` `.pkg.pb` `.repo.pb` | `/opt` (OPTS_DIR) |
| `.etc.pb` | `/etc/opt` (ETCS_DIR) |
| `.srv.pb` | `/srv` (SRVS_DIR) |

Under DIR: `bin/` (scripts), `etc/` (config, symlink to ETCS_DIR/NAME), `env`,
`env.export`, `README.md`.
