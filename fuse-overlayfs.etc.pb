---
# fuse-overlayfs.etc.pb — mount(8) helper for Type=fuse-overlayfs.
#
# Debian's fuse-overlayfs package ships only the binary; no
# /usr/sbin/mount.fuse-overlayfs helper. Without one, systemd .mount units
# cannot mount fuse-overlayfs (systemd execs mount(8), which dispatches on
# Type= to a helper), so automounted rw-overlay stacks are impossible.
#
# This playbook installs bin/mount.fuse-overlayfs and links it into
# /usr/sbin. The helper speaks the mount(8) protocol
# (mount.fuse-overlayfs <source> <dir> [-o opts]), drops the meaningless
# FUSE <source> positional, pre-creates upperdir/workdir (.mount units
# cannot ExecStartPre, and fuse-overlayfs refuses to start without them),
# and execs the real binary.
#
#   ansible-playbook -i 'localhost,' -c local fuse-overlayfs.etc.pb
#
# Consumers: rimworld.opt.pb (automounted dwarfs + rw overlay stack).
- hosts: all
  vars:
    TYPE: fuse-overlayfs
    INSTANCE: main
    PKGS:
      - fuse3
      - fuse-overlayfs
    BINS:
      # Invoked by mount(8) as root with helper-protocol args: no bin
      # helpers, no cwd change.
      - name: mount.fuse-overlayfs
        helpers: false
        basedir: False
        generated: |
          set -euo pipefail
          mp=""
          opts=""
          src_seen=0
          args=()
          while [ $# -gt 0 ]; do
            case "$1" in
              -o) opts="$2"; args+=(-o "$2"); shift 2 ;;
              -*) args+=("$1"); shift ;;
              # first positional is the mount(8) <source> (meaningless for
              # FUSE) -- drop it; the second is the mountpoint.
              *) if [ "$src_seen" = 0 ]; then src_seen=1; shift; else mp="$1"; shift; fi ;;
            esac
          done
          # .mount units cannot ExecStartPre; ensure upper/work exist.
          if [ -n "$opts" ]; then
            IFS=',' read -ra kv <<< "$opts"
            for item in "${kv[@]}"; do
              case "$item" in
                upperdir=*|workdir=*) mkdir -p "${item#*=}" ;;
              esac
            done
          fi
          exec /usr/bin/fuse-overlayfs "${args[@]}" "$mp"
    LINKS:
      - src: "{{BINS_DIR}}/mount.fuse-overlayfs"
        dest: /usr/sbin/mount.fuse-overlayfs
        scope: system
        policy: replace
  tasks:
    - import_tasks: tasks/compfuzor.includes
