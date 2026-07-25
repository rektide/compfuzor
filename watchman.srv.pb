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

    # Interactive shells: an `env` zim module exports WATCHMAN_SOCK at shell
    # startup. gen_zim generates zim-modules/watchman-env/init.zsh from the
    # mapping (one don't-stomp-per-var guard; COMPFUZOR_ENV_OVERWRITE=1 forces)
    # and a `zmodule <abspath>` declaration, plus install-user-zimfw.sh to
    # promote it into the zim host. No bespoke script, no block-in-file.
    ZIM_MODULES:
      - name: watchman-env
        phase: tools
        env:
          WATCHMAN_SOCK: "{{VAR}}/sock"
  tasks:
    - import_tasks: tasks/compfuzor.includes
