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

## Summary Table

| Pattern | Use Case | Key Variables |
|---------|----------|---------------|
| `SYSTEMD_SCOPE: user` | Direct user service flag | `SYSTEMD_SCOPE: user` |
| `USERMODE: True` | Full user-mode context | `USERMODE: True` |
| Custom script | Complex installation needs | `BINS` with install script |
| User targets | Session integration | `WantedBy: graphical-session.target` |

---

## Additional Examples

