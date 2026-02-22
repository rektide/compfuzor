# Systemd User Services in compfuzor

This document catalogs patterns for creating systemd user services (as opposed to system services) within compfuzor playbooks.

## Introduction

Systemd user services run under a user's session rather than system-wide. They are installed to `~/.config/systemd/user/` and managed with `systemctl --user`. In compfuzor, several patterns exist to configure user services:

1. **`SYSTEMD_SCOPE: user`** - Explicit flag for user scope
2. **`USERMODE: True`** - General user-mode flag (affects more than just systemd)
3. **Custom install scripts** - Manual installation to user systemd directory
4. **Target selection** - Using user-specific targets like `graphical-session.target` or `default.target`

---

## Pattern 1: `SYSTEMD_SCOPE: user`

The most direct approach for user services. Sets the systemd scope to user, causing the service to be installed and managed in the user's systemd context.

### Implementation

```yaml
SYSTEMD_SERVICE: <service-name>
SYSTEMD_SCOPE: user
```

### Example: [`rclone.srv.pb`](../rclone.srv.pb)

```yaml
SYSTEMD_SERVICE: rclone
SYSTEMD_EXEC: "rclone mount --vfs-cache-mode writes ..."
SYSTEMD_SCOPE: user
SYSTEMD_INSTANCES: True
```

The rclone service uses `SYSTEMD_SCOPE: user` to mount remote filesystems in the user context, with templated instances for different remotes.

---

## Pattern 2: `USERMODE: True`

A broader flag that indicates the entire service should run in user mode. This affects not just systemd but other aspects like installation paths and file ownership.

### Implementation

```yaml
USERMODE: True
SYSTEMD_SERVICE: True  # or service name
```

### Example: [`synergy.user.pb`](../synergy.user.pb)

```yaml
USERMODE: True
SYSTEMD_SERVICE: True
SYSTEMD_EXEC: "/usr/bin/synergys -f -d INFO --config {{ETC}}/synergy.conf"
```

Synergy (a KVM switch) uses `USERMODE: True` since it's a per-user desktop application that should run in the user's graphical session.

---

## Pattern 3: Custom Install Scripts

For more control over installation, or when service generation needs custom handling, explicit install scripts can place the service file in the user's systemd directory.

### Implementation

```yaml
SYSTEMD_LINK: False  # Disable automatic linking
BINS:
  - name: install-user.sh
    content: |
      mkdir -p ~/.config/systemd/user
      ln -sf $(pwd)/etc/<service>.service ~/.config/systemd/user/
      systemctl --user enable --now <service>
```

### Example: [`ssh-agent.srv.pb`](../ssh-agent.srv.pb)

```yaml
BINS:
  - name: install-user.sh
    content: |
      mkdir -p ~/.config/systemd/user
      ln -sf ${DIR}/etc/ssh-agent.service ~/.config/systemd/user/
      systemctl --user daemon-reload
      systemctl --user enable --now ssh-agent
```

SSH agent uses a custom script because it also needs to manage environment variables and integrate with the shell via `~/.zshrc`.

### Example: [`pw-loopback.srv.pb`](../pw-loopback.srv.pb)

```yaml
BINS:
  - name: install-user.sh
    content: |
      [ -n "$INSTALL_DIR" ] || INSTALL_DIR="$HOME/.config/systemd/user"
      mkdir -p $INSTALL_DIR
      ln -sf $(pwd)/etc/pw-loopback.service $INSTALL_DIR/
      systemctl --user enable pw-loopback.service
      systemctl --user start pw-loopback.service
```

Pipewire loopback uses this pattern with an optional `INSTALL_DIR` override for flexibility.

---

## Pattern 4: User-Session Targets

User services typically integrate with user-session targets rather than system targets. Common targets:

- `default.target` - General user services
- `graphical-session.target` - Services requiring a graphical session
- `pipewire.service` - Audio-related services

### Example: [`wob.srv.pb`](../wob.srv.pb)

```yaml
SYSTEMD_UNITS:
  After: graphical-session.target
  Wants: graphical-session.target
SYSTEMD_INSTALL:
  WantedBy: graphical-session.target
```

Wob (Wayland Overlay Bar) requires a graphical session, so it uses `graphical-session.target`.

### Example: [`ssh-agent.srv.pb`](../ssh-agent.srv.pb)

```yaml
[Install]
WantedBy: default.target
```

SSH agent uses `default.target` since it should be available throughout the user session.

---

## Pattern 7: Auto-Generated Install Scripts

When systemd units are defined, compfuzor automatically generates install scripts:

### System Units

```yaml
SYSTEMD_SERVICE: True  # or service name
# or
SYSTEMD_MOUNT: /mnt/data  # mount point name
```

Generates `bin/install-service.sh` or `bin/install-mount.sh` that:
- Links `etc/<name>.<type>` to `/etc/systemd/system/`
- Daemon-reloads only if the unit file changed
- Enables the unit

### User Units

User unit install scripts are generated based on `SYSTEMD_USER_*_INSTALL`:

```yaml
SYSTEMD_SERVICE: True
SYSTEMD_INSTALL: user  # or both
```

Generates `bin/install-service-user.sh` that:
- Links `etc/<name>.user.<type>` to `~/.config/systemd/user/<name>.<type>`
- Uses `systemctl --user` commands
- No sudo required

### Dual System + User Units

For units that need both system and user variants:

```yaml
SYSTEMD_SERVICE: True
SYSTEMD_INSTALL: both
```

Generates:
- `etc/<name>.<type>` - System unit template
- `etc/<name>.user.<type>` - User unit template
- `bin/install-<type>.sh` - Installs system unit
- `bin/install-<type>-user.sh` - Installs user unit

### Shared Install Script

All unit install scripts use a shared parameterized script at [`files/systemd/install-unit.sh`](../files/systemd/install-unit.sh):

**Defaults (sourced from `env.export`):**
- `UNIT_NAME` - defaults to `NAME` from `env.export`, else `basename $(pwd)`
- `UNIT_TYPE` - defaults to `service` (also: `socket`, `mount`, `dnssd`)
- `UNIT_FILE` - defaults to `UNIT_NAME` (use `UNIT_SUFFIX=user` for `.user.*`)

**System service (`bin/install-service.sh`):**
```bash
UNIT_NAME="my-service"
UNIT_TYPE=service
source "$(dirname "$0")/../etc/install-unit.sh"
```

**User service (`bin/install-service-user.sh`):**
```bash
UNIT_NAME="my-service"
UNIT_TYPE=service
UNIT_SUFFIX=user
USERMODE=true
source "$(dirname "$0")/../etc/install-unit.sh"
```

This installs `etc/my-service.user.service` → `~/.config/systemd/user/my-service.service` (`.user` stripped from symlink)

**System mount (`bin/install-mount.sh`):**
```bash
UNIT_NAME="my-mount"
UNIT_TYPE=mount
source "$(dirname "$0")/../etc/install-unit.sh"
```

**User mount (`bin/install-mount-user.sh`):**
```bash
UNIT_NAME="my-mount"
UNIT_TYPE=mount
UNIT_SUFFIX=user
USERMODE=true
source "$(dirname "$0")/../etc/install-unit.sh"
```

**Environment variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `USERMODE` | `false` | `true` for user units |
| `UNIT_NAME` | `NAME` or `basename $(pwd)` | Unit identifier |
| `UNIT_TYPE` | `service` | Unit type: `service`, `socket`, `mount`, `dnssd` |
| `UNIT_SUFFIX` | (empty) | Set to `user` for `.user.*` files |
| `UNIT_FILE` | `UNIT_NAME[.SUFFIX]` | Unit filename without `.{type}` |
| `SUDO` | `sudo` or `false` | `false` = no sudo |

---

## Summary Table

| Pattern | Use Case | Key Variables |
|---------|----------|---------------|
| `SYSTEMD_SCOPE: user` | Direct user service flag | `SYSTEMD_SCOPE: user` |
| `USERMODE: True` | Full user-mode context | `USERMODE: True` |
| Custom script | Complex installation needs | `BINS` with install script |
| User targets | Session integration | `WantedBy: graphical-session.target` |

---

## Pattern 5: `USERMODE: True` with Common Variables

When using `USERMODE: True`, the [`vars/common.user.yaml`](../vars/common.user.yaml) file is typically imported, which automatically sets:

```yaml
USERMODE: True

SYSTEMD_SCOPE: user
SYSTEMD_UNIT_DIR: "{{XDG_CONFIG_DIR}}/systemd/user"
```

This also remaps all standard directories to user-specific locations (`BINS_DIR`, `ETCS_DIR`, `OPTS_DIR`, etc.).

### Example: [`rtorrent.pb`](../rtorrent.pb)

```yaml
USERMODE: True
# No SYSTEMD_* variables needed - common.user.yaml handles it

LINKS:
  "~/.rtorrent.rc": "{{ETC}}/rtorrent.rc"
  "~/.torrent": "{{VAR}}"
```

rtorrent is a user-space torrent client, so `USERMODE: True` ensures everything runs under the user's context.

### Example: [`google-drive-ocamlfuse.mount.pb`](../google-drive-ocamlfuse.mount.pb)

```yaml
USERMODE: True
SYSTEMD_EXEC: google-drive-ocamlfuse -label $LABEL $MNT
SYSTEMD_EXEC_STOP: fusermount -u $MNT
SYSTEMD_TYPE: forking
```

Google Drive mount uses `USERMODE: True` to mount in the user's home directory.

---

## Pattern 6: Post-Install User Service Enablement

Some services are installed system-wide but need user-level enablement. These use a separate `install-user.sh` script.

### Example: [`vicinae.src.pb`](../vicinae.src.pb)

```yaml
BINS:
  - name: install.sh
    content: |
      cmake --install build
      sudo systemctl daemon-reload
  - name: install-user.sh
    content: |
      systemctl --user enable vicinae.service
```

Vicinae installs to system paths but the user service needs to be enabled per-user.

### Example: [`surface-dial.src.pb`](../surface-dial.src.pb)

```yaml
BINS:
  - name: install-user.sh
    exec: |
      mkdir -p ~/.config/systemd/user/
      cp ./install/surface-dial.service ~/.config/systemd/user/surface-dial.service
      systemctl --user daemon-reload
      systemctl --user enable surface-dial.service
      systemctl --user start surface-dial.service
```

Surface Dial copies an upstream service file to the user systemd directory rather than generating one.

### Example: [`gmrender-resurrect.src.pb`](../gmrender-resurrect.src.pb)

```yaml
SYSTEMD_SERVICE: True
SYSTEMD_SERVICES:
  ExecStart: "/usr/bin/gmediarender --logfile /dev/stdout"
BINS:
  - name: install-user.sh
    content: |
      ln -s $(pwd)/etc/{{NAME}}.service ~/.config/systemd/user/
```

gmediarender uses `SYSTEMD_SERVICE: True` to generate a service file, then links it manually to the user directory.

---

## File Naming Convention

Playbooks with `.user.pb` extension typically indicate user-mode services:

- [`synergy.user.pb`](../synergy.user.pb)
- [`rygel.user.pb`](../rygel.user.pb)
- [`kitty.user.pb`](../kitty.user.pb)
- [`ripgrep.user.pb`](../ripgrep.user.pb)

These often include `USERMODE: True` or target user-specific configuration directories.

---

## Quick Reference

| Variable | Effect |
|----------|--------|
| `SYSTEMD_DUAL` | Generate both system + user scope units (default: true) |
| `SYSTEMD_SCOPE` | Current scope: `system` or `user` |
| `SYSTEMD_SYSTEM_*` | Generate system unit file for type `*` (service, socket, mount, dnssd) |
| `SYSTEMD_USER_*` | Generate user unit file for type `*` |
| `SYSTEMD_INSTALL` | Install script generation: `system` \| `user` \| `both` \| `none` \| `true` \| `false` |
| `SYSTEMD_SYSTEM_*_INSTALL` | Generate install script for system unit type |
| `SYSTEMD_USER_*_INSTALL` | Generate install script for user unit type |
| `SYSTEMD_UNIT_DIR` | Override unit installation path |
| `USERMODE: True` | Enables user mode + sets SYSTEMD_DUAL:false, SYSTEMD_INSTALL:user |
| `SYSTEMD_INSTALL_BYPASS: True` | Skip generating all install scripts |
| `SYSTEMD_LINK: False` | Disables automatic unit linking |
| `WantedBy: graphical-session.target` | Start with graphical session |
| `WantedBy: default.target` | Start with user session |
| `BindsTo: pipewire.service` | Tie lifecycle to another service |

### Per-Scope Per-Unit-Type Gates

| Variable | Default | Controls |
|----------|---------|----------|
| `SYSTEMD_SYSTEM_SERVICE` | true | Generate system .service |
| `SYSTEMD_SYSTEM_SOCKET` | true | Generate system .socket |
| `SYSTEMD_USER_SERVICE` | true | Generate user .user.service |
| `SYSTEMD_USER_SOCKET` | true | Generate user .socket |

### Generated Files

| Condition | Generated Files |
|-----------|-----------------|
| `SYSTEMD_SERVICE` or `SYSTEMD_SERVICES` defined | `etc/<name>.service` (system), `etc/<name>.user.service` (user) |
| `SYSTEMD_MOUNT` or `SYSTEMD_MOUNTS` defined | `etc/<name>.mount` (system), `etc/<name>.user.mount` (user) |
| `SYSTEMD_SOCKET` or `SYSTEMD_SOCKETS` defined | `etc/<name>.socket` (system), `etc/<name>.user.socket` (user) |
| `SYSTEMD_SYSTEM_*_INSTALL` | `bin/install-<type>.sh` |
| `SYSTEMD_USER_*_INSTALL` | `bin/install-<type>-user.sh` |
| Any unit defined | `etc/install-unit.sh` (shared script) |

### File Naming Convention

| Scope | etc/ filename | Symlink destination |
|-------|---------------|---------------------|
| System | `<name>.<type>` | `/etc/systemd/system/<name>.<type>` |
| User | `<name>.user.<type>` | `~/.config/systemd/user/<name>.<type>` |

The `.user` suffix is stripped when creating the symlink so systemd sees `foo.service` not `foo.user.service`.

Applies to all unit types: `service`, `socket`, `mount`, `dnssd`.

### Default Behavior

When any systemd unit is defined (e.g., `SYSTEMD_MOUNT` or `SYSTEMD_MOUNTS.Where`):

**Default (USERMODE=false):**
- Generates both `etc/<name>.<type>` and `etc/<name>.user.<type>`
- Generates `bin/install-<type>.sh` (SYSTEMD_INSTALL=system)
- User unit file available but no install script

**With USERMODE=true:**
- Generates only `etc/<name>.<type>` (no .user variant, SYSTEMD_DUAL=false)
- Generates `bin/install-<type>-user.sh` (SYSTEMD_INSTALL=user)

**To get both install scripts:**
```yaml
SYSTEMD_INSTALL: both
```


