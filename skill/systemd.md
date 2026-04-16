# compfuzor: systemd unit generation

## How it works

Compfuzor generates systemd unit files from playbook variables and manages their lifecycle through auto-generated install scripts.

The pipeline (in `tasks/compfuzor/vars_systemd_unit.tasks`) runs during the VARIABLES phase and:

1. Detects which unit types are needed by checking for `SYSTEMD_SERVICES`, `SYSTEMD_SOCKETS`, `SYSTEMD_MOUNTS`, etc.
2. Merges playbook values with defaults from `vars/systemd.yaml`
3. Generates unit file content via `files/systemd.unit` template
4. Adds unit files to `ETC_FILES`
5. Adds `install-unit.sh` + `install-<type>[-user].sh` scripts to `BINS`

## Three section dicts

Every unit type has up to three section dicts that map to `[Unit]`, `[Service]`/type-specific, and `[Install]`:

| Variable | Section | Purpose |
|---|---|---|
| `SYSTEMD_UNITS` | `[Unit]` | Description, ordering, dependencies, conditions |
| `SYSTEMD_SERVICES` | `[Service]` | ExecStart, Type, Restart, Environment, sandboxing, resource limits |
| `SYSTEMD_INSTALLS` | `[Install]` | WantedBy, RequiredBy, Alias, Also |

For other unit types, the middle section changes:

| Unit type | Section dict | Generated section |
|---|---|---|
| service | `SYSTEMD_SERVICES` | `[Service]` |
| socket | `SYSTEMD_SOCKETS` | `[Socket]` |
| mount | `SYSTEMD_MOUNTS` | `[Mount]` |
| timer | `SYSTEMD_TIMERS` | `[Timer]` |
| path | `SYSTEMD_PATHS` | `[Path]` |
| slice | `SYSTEMD_SLICES` | `[Slice]` |
| scope | `SYSTEMD_SCOPES` | `[Scope]` |
| automount | `SYSTEMD_AUTOMOUNTS` | `[Automount]` |
| swap | `SYSTEMD_SWAPS` | `[Swap]` |
| target | `SYSTEMD_TARGETS` | (only `[Unit]` + `[Install]`) |
| network | `SYSTEMD_NETWORK` | `[Match]`, `[Network]`, etc. |
| netdev | `SYSTEMD_NETDEV` | `[Match]`, `[NetDev]`, etc. |

See `SYSTEMD_TYPE_CONFIG` in `vars/systemd.yaml` for the full mapping.

## Auto-merged defaults

Playbook values merge on top of these defaults (from `vars/systemd.yaml`):

```yaml
SYSTEMD_UNITS_DEFAULT:
  Description: "{{ NAME }}"
  DefaultDependencies: true

SYSTEMD_SERVICES_DEFAULT:
  Type: simple
  Restart: on-failure
  RestartSec: 5

SYSTEMD_INSTALLS_DEFAULT:
  WantedBy: multi-user.target  # or default.target for user scope
```

You get these automatically. Override any key by setting it in your playbook's dict.

## Minimal example

```yaml
# lact.srv.pb
SYSTEMD_SERVICES:
  ExecStart: lact daemon
```

This produces a service with Description from NAME, Type=simple, Restart=on-failure, RestartSec=5, WantedBy=multi-user.target.

## Full service example

```yaml
SYSTEMD_UNITS:
  Description: Lock SSH agent before sleep
  Before: sleep.target suspend.target hibernate.target hybrid-sleep.target
SYSTEMD_SERVICES:
  Type: oneshot
  ExecStart: /usr/bin/ssh-add -D
  Environment: "SSH_AUTH_SOCK=%t/ssh-agent.sock"
SYSTEMD_INSTALLS:
  WantedBy: sleep.target suspend.target hibernate.target hybrid-sleep.target
```

## Mount unit example

```yaml
SYSTEMD_MOUNT: "mnt-data"  # unit name (escaped path)
SYSTEMD_UNITS:
  After: local-fs.target
SYSTEMD_MOUNTS:
  What: /dev/sda1
  Where: /mnt/data
  Type: ext4
  Options: defaults
SYSTEMD_INSTALLS:
  WantedBy: local-fs.target
```

## SYSTEMD_EXEC shorthand

For simple services, `SYSTEMD_EXEC` sets `ExecStart` without needing the full `SYSTEMD_SERVICES` dict:

```yaml
SYSTEMD_EXEC: "{{opt}}/my-daemon --config {{ETC}}/config"
```

You can still set `SYSTEMD_SERVICES` alongside for additional properties like sandboxing.

## USERMODE and systemd

When `USERMODE: True`, `common.user.yaml` sets:

```yaml
SYSTEMD_SCOPE: user
SYSTEMD_UNIT_DIR: ~/.config/systemd/user
SYSTEMD_DUAL: false
SYSTEMD_INSTALL: user
```

- `WantedBy` defaults to `default.target` (not `multi-user.target`)
- Install script uses `systemctl --user` (no sudo)
- Units symlink to `~/.config/systemd/user/`
- Systemd specifiers like `%t` ($XDG_RUNTIME_DIR), `%h` ($HOME) work in directives

## Install scripts

`vars_systemd_unit.tasks` auto-generates install scripts in `bin/`:

| Script | When generated |
|---|---|
| `install-unit.sh` | Always, when any units detected. Shared helper. |
| `install-service.sh` | System-scope service unit |
| `install-service-user.sh` | User-scope service unit |
| `install-socket.sh` / `install-socket-user.sh` | Socket units |
| etc. | One per unit type per scope |

`install-unit.sh` sources `env.export`, symlinks the unit file, runs `daemon-reload`, and enables the unit.

## Unit naming

By default the unit is named `{{NAME}}`. Override with `SYSTEMD_SERVICE` (or `SYSTEMD_SOCKET`, `SYSTEMD_MOUNT`, etc.):

```yaml
SYSTEMD_SERVICE: my-custom-name   # produces my-custom-name.service
```

Set to `True` to use the playbook NAME.

For instanced units (template units with `@`):

```yaml
SYSTEMD_INSTANCES: ["inst1", "inst2"]  # generates name@.service, enables name@inst1 name@inst2
```

## Multiple units (SYSTEMD_ROOTS)

To define multiple units of different types in one playbook, use nested dicts and `SYSTEMD_ROOTS`:

```yaml
SYSTEMD_ROOTS: [myMount, myAutoMount]

myMount:
  SYSTEMD_MOUNT: mnt-data
  SYSTEMD_MOUNTS:
    What: /dev/sda1
    Where: /mnt/data
    Type: ext4

myAutoMount:
  SYSTEMD_AUTOMOUNT: mnt-data
  SYSTEMD_AUTOMOUNTS:
    Where: /mnt/data
    TimeoutIdleSec: 300
```

## Systemd targets and hooks

### Sleep / hibernate hooks

Systemd has sleep-related targets. Both system and user instances can use them:

| Target | When activated |
|---|---|
| `sleep.target` | Any suspend/hibernate/hybrid-sleep |
| `suspend.target` | Suspend to RAM |
| `hibernate.target` | Suspend to disk |
| `hybrid-sleep.target` | Suspend to RAM + disk |

For user-scope services, `systemd-logind` propagates the sleep state to the user instance via the `PrepareForSleep` D-Bus signal, which activates `sleep.target` in the user's systemd.

To run a oneshot action before sleep:

```yaml
USERMODE: True
SYSTEMD_UNITS:
  Before: sleep.target suspend.target hibernate.target hybrid-sleep.target
SYSTEMD_SERVICES:
  Type: oneshot
  ExecStart: /path/to/my-script
SYSTEMD_INSTALLS:
  WantedBy: sleep.target suspend.target hibernate.target hybrid-sleep.target
```

### Graphical session hooks

| Target | Use case |
|---|---|
| `graphical-session.target` | After user's graphical session is up |
| `graphical-session-pre.target` | Before graphical session starts |

### Network and filesystem targets

| Target | Use case |
|---|---|
| `network-online.target` | Wait for network connectivity |
| `network.target` | Network stack is up (not necessarily connected) |
| `local-fs.target` | Local filesystems mounted |
| `remote-fs.target` | Remote filesystems mounted |
| `multi-user.target` | System fully booted, multi-user ready |
| `default.target` | User session ready |

## Bypass flags

| Flag | Effect |
|---|---|
| `SYSTEMD_BYPASS: True` | Skip all systemd processing |
| `SYSTEMD_INSTALL_BYPASS: True` | Skip ETC_FILES generation and install scripts |
| `SYSTEMD_THUNK_BYPASS: True` | Skip the legacy `systemd.thunk.tasks` enable/restart |

## Key files

| File | Purpose |
|---|---|
| `vars/systemd.yaml` | Defaults, type config, phrase lists, scope paths |
| `files/systemd.unit` | New-style section-based template (current) |
| `files/systemd.service` | Old-style phrase-based template (legacy) |
| `files/systemd/install-unit.sh` | Shared install helper script |
| `tasks/compfuzor/vars_systemd_unit.tasks` | Unit generation logic (ETC_FILES + BINS) |
| `tasks/systemd.unit.includes` | Legacy unit generation (being replaced) |
| `tasks/systemd.thunk.tasks` | Legacy enable/restart logic |
