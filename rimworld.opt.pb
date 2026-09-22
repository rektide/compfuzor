---
# rimworld.opt.pb — dwarfs automount + fuse-overlayfs rw layer for the
# RimWorld jc141 repack at /mnt/bitblaster/torrent/RimWorld-jc141.
#
# Replaces the jc141 start.n.sh mount/unmount lifecycle with systemd units:
#
#   files/game-root.dwarfs  --(dwarfs, ro)-->  files/.game-root-mnt
#            automounted on access (mnt-...-game\x2droot\x2dmnt.automount),
#            unmounted after TimeoutIdleSec when idle.
#   files/.game-root-mnt + files/overlay-storage
#            --(fuse-overlayfs, rw)-->  files/game-root
#            mounted by rimworld-overlay.service (oneshot, RemainAfterExit),
#            started/stopped by bin/run.sh around the game.
#
# The rw layer is where mods/updates land (overlay-storage survives
# unmounts); the dwarfs image stays pristine. squash_to_uid/gid make the
# root-mounted overlay usable by the game.
#
# mount(8) dispatches Type=dwarfs to /usr/sbin/mount.dwarfs, which the
# LINKS subsystem points at bin/mount.dwarfs — a wrapper around the
# release's bundled static dwarfs multiplexer (files/dwarfs-binary), so
# no system dwarfs install is required.
#
#   ansible-playbook -i 'localhost,' -c local rimworld.opt.pb
#   DIR/bin/run.sh          # play
#   systemctl status rimworld-overlay.service
#   systemctl stop rimworld-overlay.service   # unmount rw layer; ro layer
#                                             # follows on idle timeout
#
# Vars (optional, -e overrides):
#   game_dir    release root (default the path above)
#   idle        automount TimeoutIdleSec (default 10min)
#   cachesize   dwarfs block cache, jc141 default 25% of RAM (e.g. 4g)
- hosts: all
  vars:
    TYPE: rimworld
    INSTANCE: main
    PKGS:
      - fuse3
      - fuse-overlayfs
    GAME_DIR: "{{game_dir|default('/mnt/bitblaster/torrent/RimWorld-jc141')}}"
    GAME_FILES: "{{GAME_DIR}}/files"
    IMAGE: "{{GAME_FILES}}/game-root.dwarfs"
    DWARFS_BIN: "{{GAME_FILES}}/dwarfs-binary"
    # jc141 private mount layout (files/.game-root-mnt is the ro layer)
    LOWER: "{{GAME_FILES}}/.game-root-mnt"
    MERGED: "{{GAME_FILES}}/game-root"
    UPPER: "{{GAME_FILES}}/overlay-storage"
    WORK: "{{GAME_FILES}}/.game-root-work"
    LOWER_UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ LOWER) }}"
    OVERLAY_UNIT: "{{TYPE}}-overlay"
    SQUASH_UID: "{{ansible_user_uid}}"
    SQUASH_GID: "{{ansible_user_gid}}"
    # jc141: cachesize = 25% of MemTotal; tidy evicts after 30m idle
    CACHESIZE: "{{cachesize|default((ansible_memtotal_mb*1024*25/100)|int ~ 'k')}}"
    DWARFS_OPTS: "ro,allow_other,cachesize={{CACHESIZE}},clone_fd,tidy_strategy=time,tidy_interval=15m,tidy_max_age=30m"
    ENV:
      GAME_DIR: "{{GAME_DIR}}"
      IMAGE: "{{IMAGE}}"
      LOWER: "{{LOWER}}"
      MERGED: "{{MERGED}}"
      UPPER: "{{UPPER}}"
      WORK: "{{WORK}}"
      OVERLAY_UNIT: "{{OVERLAY_UNIT}}"
      LOWER_UNIT: "{{LOWER_UNIT}}"
    BINS:
      # mount(8) helper for Type=dwarfs .mount units. Nuclear (helpers:
      # false): invoked by mount as root with helper-protocol args; must
      # only exec the bundled binary (pinned to the image's dwarfs version).
      - name: mount.dwarfs
        helpers: false
        basedir: False
        generated: |
          exec {{DWARFS_BIN}} --tool=dwarfs "$@"
      # Game launcher: up-stack, play, down-stack.
      - name: run.sh
        generated: |
          set -euo pipefail
          sudo systemctl start "${OVERLAY_UNIT}.service"
          cleanup() { sudo systemctl stop "${OVERLAY_UNIT}.service"; }
          trap cleanup EXIT INT TERM
          cd "${MERGED}"
          ./start_RimWorld.sh "$@"
    LINKS:
      - src: "{{BINS_DIR}}/mount.dwarfs"
        dest: /usr/sbin/mount.dwarfs
        scope: system
        policy: replace
    SYSTEMD_ROOTS:
      - DWARFS_MOUNT
      - DWARFS_AUTOMOUNT
      - OVERLAY_SERVICE
    DWARFS_MOUNT:
      SYSTEMD_MOUNT: "{{LOWER_UNIT}}"
      # .mount units never enable directly; the automount pulls it in.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs ro layer {{IMAGE}}"
      SYSTEMD_MOUNTS:
        What: "{{IMAGE}}"
        Where: "{{LOWER}}"
        Type: dwarfs
        Options: "{{DWARFS_OPTS}}"
        TimeoutSec: 60
    DWARFS_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{LOWER_UNIT}}"
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs lazy mount {{LOWER}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{LOWER}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('10min')}}"
    OVERLAY_SERVICE:
      SYSTEMD_SERVICE: "{{OVERLAY_UNIT}}"
      # link-only: run.sh starts/stops it around the game
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld fuse-overlayfs rw layer {{MERGED}}"
        # Requires the automount so the autofs trigger exists before
        # fuse-overlayfs opens the lowerdir (access mounts the dwarf).
        Requires: "{{LOWER_UNIT}}.automount"
        After: "{{LOWER_UNIT}}.automount"
      SYSTEMD_SERVICES:
        Type: oneshot
        RemainAfterExit: true
        Restart: "no"
        ExecStartPre: /usr/bin/mkdir -p {{MERGED}} {{UPPER}} {{WORK}}
        ExecStart: /usr/bin/fuse-overlayfs -o lowerdir={{LOWER}},upperdir={{UPPER}},workdir={{WORK}},squash_to_uid={{SQUASH_UID}},squash_to_gid={{SQUASH_GID}},allow_other {{MERGED}}
        ExecStop: /usr/bin/fusermount3 -u {{MERGED}}
  tasks:
    # jc141 ships files/dwarfs-binary non-executable and chmod +xes it in
    # actions.sh on every run; the systemd mount.dwarfs helper path has no
    # such step, so the playbook owns it (idempotent).
    - name: "ensure bundled dwarfs binary is executable"
      file: path={{DWARFS_BIN}} mode=a+x
    - import_tasks: tasks/compfuzor.includes
