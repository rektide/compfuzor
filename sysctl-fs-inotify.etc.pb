---
# Raise inotify limits so many concurrent opencode/editor sessions can
# coexist without exhausting the watch pool.
#
# Use case: opencode watches the project tree on startup. A single session
# run in a large tree (~/archive) consumed ~63.5k of the default 65536
# fs.inotify.max_user_watches, so new opencode launches elsewhere failed
# with inotify_add_watch ENOSPC and stalled at startup before logging.
# With ~60 long-lived opencode processes this is trivial to hit.
#
# watches = per-inode entries on an inotify fd; ~1KB each, non-swappable,
#   and the limit that actually binds. 65536 -> 1048576.
# instances = inotify_init() fds (one per process); rarely the cap.
#   1024 -> 8192 for headroom.
- hosts: all
  vars:
    TYPE: fs-inotify
    SYSCTL:
      fs.inotify.max_user_watches: 1048576
      fs.inotify.max_user_instances: 8192
    BINS:
      # Installed as `inotify-status` (not status.sh) to avoid colliding
      # with k3s-server's status.sh in GLOBAL_BINS_DIR. Read-only: reports
      # per-user inotify watch/instance usage and top consumers; --sudo
      # for system-wide.
      - name: inotify-status
        src: status.sh
        raw: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
