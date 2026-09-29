---
# rimworld.opt.pb — automounted dwarfs + rw-overlay stack for the RimWorld
# jc141 repack at /mnt/bitblaster/torrent/RimWorld-jc141.
#
# Two system automounts; access composes the whole stack, idle tears it
# down. No services, no cleanup logic, no launcher:
#
#   /mnt/dwarfs/rimworld   ro dwarfs layer (Type=dwarfs, system dwarfs)
#   /mnt/rimworld          rw overlay (Type=fuse-overlayfs: lower=dwarfs,
#                           upper/work under STATE_DIR; what Lutris/games
#                           point at — the game tree with mods/updates)
#
#   ls /mnt/rimworld  ->  automount triggers overlay mount  ->  fuse-overlayfs
#                         opens lowerdir  ->  triggers dwarfs automount
#   idle               ->  overlay unmounts; dwarfs follows on its own idle
#
# Dependencies:
#   dwarfs.src.pb        system dwarfs + /usr/sbin/mount.dwarfs bridge
#   fuse-overlayfs.etc.pb  /usr/sbin/mount.fuse-overlayfs helper (Debian
#                          ships none; .mount units cannot mount without it)
#
# All mutable state lives under STATE_DIR (one portable per-game dir,
# XDG-flavored default): overlay/{upper,work} today, a fake game $HOME
# (jc141's native-docs concept) later. The torrent dir stays pristine —
# only the image is read from it.
#
#   ansible-playbook -i 'localhost,' -c local rimworld.opt.pb
#   ls /mnt/rimworld                          # play goes here (Lutris etc.)
#
# Vars (optional, -e overrides):
#   game_dir    release root (default the path above)
#   ro_where    ro mountpoint (default /mnt/dwarfs/rimworld)
#   where       rw mountpoint (default /mnt/rimworld)
#   state_dir   per-game state root (default ~/.local/share/rimworld)
#   idle        automount TimeoutIdleSec (default 10min)
#   cachesize   dwarfs block cache, default 25% of RAM (e.g. 4g)
- hosts: all
  vars:
    TYPE: rimworld
    INSTANCE: main
    GAME_DIR: "{{game_dir|default('/mnt/bitblaster/torrent/RimWorld-jc141')}}"
    IMAGE: "{{GAME_DIR}}/files/game-root.dwarfs"
    RO_WHERE: "{{ro_where|default('/mnt/dwarfs/rimworld')}}"
    WHERE: "{{where|default('/mnt/rimworld')}}"
    STATE_DIR: "{{state_dir|default(ansible_user_dir ~ '/.local/share/' + TYPE)}}"
    UPPER: "{{STATE_DIR}}/overlay/upper"
    WORK: "{{STATE_DIR}}/overlay/work"
    RO_UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ RO_WHERE) }}"
    RW_UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ WHERE) }}"
    SQUASH_UID: "{{ansible_user_uid}}"
    SQUASH_GID: "{{ansible_user_gid}}"
    # jc141 defaults: cachesize = 25% of MemTotal; tidy evicts after 30m
    CACHESIZE: "{{cachesize|default((ansible_memtotal_mb*1024*25/100)|int ~ 'k')}}"
    DWARFS_OPTS: "ro,allow_other,cachesize={{CACHESIZE}},clone_fd,tidy_strategy=time,tidy_interval=15m,tidy_max_age=30m"
    OVERLAY_OPTS: "lowerdir={{RO_WHERE}},upperdir={{UPPER}},workdir={{WORK}},squash_to_uid={{SQUASH_UID}},squash_to_gid={{SQUASH_GID}},allow_other"
    DIRS:
      - "{{UPPER}}"
      - "{{WORK}}"
    ENV:
      GAME_DIR: "{{GAME_DIR}}"
      IMAGE: "{{IMAGE}}"
      RO_WHERE: "{{RO_WHERE}}"
      WHERE: "{{WHERE}}"
      STATE_DIR: "{{STATE_DIR}}"
      UPPER: "{{UPPER}}"
      WORK: "{{WORK}}"
    SYSTEMD_ROOTS:
      - RO_MOUNT
      - RO_AUTOMOUNT
      - RW_MOUNT
      - RW_AUTOMOUNT
    RO_MOUNT:
      SYSTEMD_MOUNT: "{{RO_UNIT}}"
      # .mount units never enable directly; the automount pulls them in.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs ro layer {{IMAGE}}"
      SYSTEMD_MOUNTS:
        What: "{{IMAGE}}"
        Where: "{{RO_WHERE}}"
        Type: dwarfs
        Options: "{{DWARFS_OPTS}}"
        TimeoutSec: 60
    RO_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{RO_UNIT}}"
      SYSTEMD_UNITS:
        Description: "rimworld dwarfs lazy mount {{RO_WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{RO_WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('10min')}}"
    RW_MOUNT:
      SYSTEMD_MOUNT: "{{RW_UNIT}}"
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "rimworld rw overlay {{WHERE}}"
        # Require the ro MOUNT, not just its automount: with only the
        # automount required, the overlay helper can race ahead of the
        # dwarfs trigger, scan an untriggered (empty) lowerdir, and mount
        # an empty view that never re-scans. Requiring the .mount makes
        # systemd mount the dwarfs layer first, on demand.
        Requires: "{{RO_UNIT}}.mount"
        After: "{{RO_UNIT}}.mount"
      SYSTEMD_MOUNTS:
        What: overlay
        Where: "{{WHERE}}"
        Type: fuse-overlayfs
        Options: "{{OVERLAY_OPTS}}"
        TimeoutSec: 60
    RW_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{RW_UNIT}}"
      SYSTEMD_UNITS:
        Description: "rimworld rw overlay lazy mount {{WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('10min')}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
