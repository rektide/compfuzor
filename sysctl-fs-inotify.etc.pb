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
#   and the limit that actually binds. 65536 -> 16777216 (2026-08-31: the
#   1048576 bump was exhausted — watchwoman spammed
#   `Error { kind: MaxFilesWatch }` (inotify_add_watch ENOSPC) crawling
#   node_modules-heavy roots alongside ~60 opencode sessions). 3M is a
#   deliberately bounded ceiling; the managed watcher status reporters show
#   service-only consumption, while usage.sh shows the whole user's pool.
#   Per-unit scoping in general (any service/slice cgroup, subtree rollup)
#   lives in the status subsystem's status-proc.sh — status-inotify.sh
#   keeps --unit as this owner's convenience alias for the same count.
# instances = inotify_init() fds (one per process); rarely the cap.
#   1024 -> 8192 for headroom.
# queued_events = per-instance kernel event-queue depth; bursts faster than
#   the consumer drains drop events (IN_Q_OVERFLOW). Default 16384 is ample,
#   pinned here for completeness.
- hosts: all
  vars:
    TYPE: fs-inotify
    STATUSES:
      # Per-user pool consumption as a status.sh reporter (usage.sh stays
      # the interactive top-consumers view).
      - status-inotify.sh
    KERNEL_SYSCTL:
      fs.inotify.max_user_watches: 3000000  # default 65536
      fs.inotify.max_user_instances: 8192   # default 1024
      fs.inotify.max_queued_events: 65536 # default 16384
    BINS:
      # usage.sh: read-only per-user inotify watch/instance consumption report
      # (top consumers); --sudo for system-wide. Distinct from status-sysctl.ts,
      # which reports sysctl drift.
      - name: usage.sh
        basedir: false
      - name: status-inotify.sh
        # status.sh reporter: the current user's TOTAL watches/instances vs
        # the pools this playbook owns, top consumers, drift at 90% of
        # either pool (exhaustion poisons every watcher on the user).
        # --unit UNIT scopes to one systemd --user unit's cgroup; for
        # arbitrary per-unit scoping prefer the status subsystem's generic
        # status-proc.sh (any scope, subtree rollup, more counters).
        basedir: false
  tasks:
    - import_tasks: tasks/compfuzor.includes
