---
# afk-dim.srv.pb — session idle dimming for the umbriel graphical session.
#
# USERMODE: everything user-scope. Binary comes from afk-dim.src.pb
# (/usr/local/bin/afk-dim, copied from the dev checkout — RUST_COPY). Config
# is compfuzor-owned: {{DIR}}/etc/config.toml renders from ETC_FILES below;
# edits belong in this playbook, not in the deployed file.
#
# Unit lifecycle binds to the graphical session (PartOf + WantedBy
# graphical-session.target): starts with the session, stops — restoring
# brightness — when it ends. afk-dim handles SIGINT and SIGTERM by restoring
# brightness before exit (ctrlc termination feature), so systemd stops are
# graceful. Restart=always: the wayland-idle backend exits when the
# compositor connection drops, and systemd relaunches until the session
# socket returns (in-process reconnect: beads afk-wayland-reconnect).
#
# Config reflects the workhorse display reality (2026-10-09):
#   DP-3 Acer XV275K P3 → /dev/i2c-8, DDC/CI (VCP 2.1) — the only dimmable
#     display.
#   DP-2 christmann CH7218 → no DDC/CI (slave 0x37 unresponsive) — cannot
#     be hardware-dimmed; see the afk-dim design notes for wlr-gamma /
#     wlr-output-power paths that could cover DDC-less displays.
# Umbriel's IPC is niri-like but wire-incompatible with niri-ipc, so the
# niri-off provider is unusable here; the idle side needs no IPC at all
# (ext-idle-notify-v1 over the session socket, WAYLAND_DISPLAY defaults to
# wayland-1 in-code).
- hosts: all
  vars:
    TYPE: afk-dim
    INSTANCE: main
    USERMODE: True
    # Unit name: afk-dim.service (not the afk-dim-main NAME default).
    SYSTEMD_SERVICE: afk-dim
    SYSTEMD_UNITS:
      Description: Dim displays when the Wayland session goes idle
      Documentation: https://github.com/rektide/afk-dim
      After: graphical-session.target
      PartOf: graphical-session.target
    SYSTEMD_SERVICES:
      ExecStart: /usr/local/bin/afk-dim --config %h/.local/srv/afk-dim-main/etc/config.toml
      Restart: always
      RestartSec: 5
    SYSTEMD_INSTALLS:
      WantedBy: graphical-session.target
    ETC_FILES:
      - name: config.toml
        content: |
          # afk-dim — umbriel session on workhorse
          # Managed by compfuzor (afk-dim.srv.pb); edit the playbook, not this file.
          dim_level = 5

          [wayland-idle]
          timeout_ms = 300000
          track = "idle"

          [brightness.acer-xv275k]
          provider = "ddccontrol"
          key = "/dev/i2c-8"
          register = "0x10"
          dim_level = 5
  tasks:
    - import_tasks: tasks/compfuzor.includes
