---
# Watchman file-watcher as a managed **user** systemd service.
#
# WHY A USER SERVICE: watchman is inherently per-user (state dir keyed by
# username, per-user inotify watch limits). The previous system-unit form here
# was never the unit actually running — the auto-started ad-hoc daemon from
# /usr/local/src/watchman-git was. This makes `systemctl --user status watchman`
# the source of truth: known state/log/socket/pid, restartable, journalable.
#
# Binary comes from watchman.src.pb (getdeps build → /usr/local/bin/watchman).
#
# ~/src PARENT-REPO FOOTGUN: ~/src is itself a .git+.jj repo. watchman resolves
# `watch-project ~/src/<repo>` UP to the nearest VCS root, so it climbs to ~/src
# and crawls the whole tree (~135 roots, 1M+ watches) → poison state → jj (which
# uses watchman as its fsmonitor backend) hangs on every status/commit. A
# .watchmanconfig / root_files guard in ~/src itself is the durable fix; tracked
# in ticket compfuzor-watchman-service.
- hosts: all
  vars:
    TYPE: watchman
    USERMODE: True

    VAR_DIR: True
    VAR_FILES:
      - name: state
        content: "{}"

    # Publish the watchman socket to the systemd user manager (and D-Bus
    # activation env) so other user services and D-Bus-launched apps can find
    # it without `watchman get-sockname`. Clients use $WATCHMAN_SOCK per
    # https://facebook.github.io/watchman/docs/socket-interface.
    # See tasks/compfuzor/vars_systemd_env.tasks: SYSTEMD_ENV -> ExecStartPost
    # `systemctl --user set-environment` + `dbus-update-activation-environment`.
    SYSTEMD_ENV:
      WATCHMAN_SOCK: "{{VAR}}/sock"

    SYSTEMD_SERVICES:
      ExecStart: "watchman --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/sock --logfile={{VAR}}/log"
      Restart: always
      RestartSec: "2s"

    # Interactive shells: files/watchman/watchman-env.zsh ships as a LOCAL
    # zimfw module (source is a .zsh -> gen_zim renders it under
    # zim-modules/watchman-env/init.zsh and emits a `zmodule <abspath>`
    # declaration). It exports WATCHMAN_SOCK, defaulting to NOT stomping an
    # existing value (COMPFUZOR_ENV_OVERWRITE=1 forces it). gen_zim also
    # generates install-user-zimfw.sh to promote the declaration into the zim
    # host, so this playbook declares no install scripts of its own.
    ZIM_MODULES:
      - source: watchman-env.zsh
        phase: tools
        comment: export WATCHMAN_SOCK at shell startup (don't stomp unless COMPFUZOR_ENV_OVERWRITE)
  tasks:
    - import_tasks: tasks/compfuzor.includes
