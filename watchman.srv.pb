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
# ROOT GUARD (ticket compfuzor-watchman-service scope item 2):
# The bare `watchman` client (no $WATCHMAN_SOCK) connects to a compile-time-
# default socket and will happily `watch-project` any path. If that path is a
# huge tree (e.g. ~/src with ~17k subdirs / 170+ project roots / 1M+ inotify
# watches), watchman enters poison state and jj — which uses watchman as its
# fsmonitor backend — hangs on every status/commit. The original ticket
# hypothesis was that ~/src being a .git+.jj repo caused watchman to climb;
# that turns out to no longer be the case (~/src is no longer a VCS repo as
# of 2026-07), but the broader footgun remains: `watch-project ~/src` just
# watches ~/src directly and crawls it.
#
# The durable fix is a global root_files guard:
#   { "root_files": [".git",".hg",".jj"], "enforce_root_files": true,
#     "ignore_dirs": [<build trees>] }
# With `enforce_root_files: true`, watchman walks UP from the requested path
# to the nearest dir containing a root_files marker, refusing if none exists.
# So `watch-project ~/src/<repo>` resolves to <repo> (which has .git/.jj);
# `watch-project ~/src` is refused outright (no marker in ~/src, ~, or /).
#
# HOW THE CONFIG IS OWNED, FULLY USER-MODE:
# Watchman reads its global config from `$WATCHMAN_CONFIG_FILE` (verified in
# WatchmanConfig.cpp:28 + website/docs/config.md:20); the binary's only other
# global path is the compile-time `/etc/watchman.json`, which we deliberately
# do NOT touch. We emit the config as an ETC artifact at {{ETC}}/watchman.json
# (visible at ~/.config/watchman-main/watchman.json via the etc symlink) and
# publish `WATCHMAN_CONFIG_FILE` to:
#   - the unit's own Environment        (the managed daemon reads it at startup)
#   - SYSTEMD_ENV → user manager + D-Bus (other user units + D-Bus-launched apps)
#   - the watchman-env zim module        (interactive shells)
# Together with $WATCHMAN_SOCK (same three channels), this guarantees any
# watchman invocation in our user session — managed daemon, D-Bus app, or
# shell command — talks to our daemon under our config. No ad-hoc unguarded
# daemons, no /etc writes, no sudo. Bypass: -e ROOT_GUARD_BYPASS=True.
#
# KNOWN LIMITATION (as of watchman HEAD 54602bcad, ver 20260708):
# The daemon reads $WATCHMAN_CONFIG_FILE and parses the JSON (verified via
# strace: openat + read of our config file succeed; invalid JSON surfaces a
# parse error in journald). BUT cfg_get_json("enforce_root_files") returns
# nullopt at runtime — a wrong-type value ("not_a_bool") does NOT trigger
# the logf(FATAL) guard in cfg_compute_root_files (WatchmanConfig.cpp:233),
# and watch-project /tmp succeeds despite no root marker up the tree. The
# keys are not reaching configState.global_cfg for reasons not yet
# identified (the call chain parse_cmdline → cfg_load_global_config_file →
# loadSystemConfig looks correct in source). The guard config is emitted
# correctly and will take effect once the daemon-side bug is resolved;
# meanwhile the SYSTEMD_ENV + ZIM_MODULES wiring still ensures all clients
# route to this managed daemon. Tracked in compfuzor-watchman-service.
- hosts: all
  vars:
    TYPE: watchman
    USERMODE: True

    VAR_DIR: True
    VAR_FILES:
      - name: state
        content: "{}"

    # Publish watchman discovery vars to the systemd user manager (and D-Bus
    # activation env) so other user services and D-Bus-launched apps find the
    # socket AND inherit the config-file path without `watchman get-sockname`.
    #   WATCHMAN_SOCK         → https://facebook.github.io/watchman/docs/socket-interface
    #   WATCHMAN_CONFIG_FILE  → WatchmanConfig.cpp:28 (overrides /etc/watchman.json)
    # See tasks/compfuzor/vars_systemd_env.tasks: SYSTEMD_ENV -> ExecStartPost
    # `systemctl --user set-environment` + `dbus-update-activation-environment`.
    SYSTEMD_ENV:
      WATCHMAN_SOCK: "{{VAR}}/sock"
      WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    SYSTEMD_SERVICES:
      ExecStart: "watchman --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/sock --logfile={{VAR}}/log"
      Environment:
        - "WATCHMAN_CONFIG_FILE={{ETC}}/watchman.json"
      Restart: always
      RestartSec: "2s"

    # Interactive shells: an `env` zim module exports WATCHMAN_SOCK and
    # WATCHMAN_CONFIG_FILE at shell startup. gen_zim generates
    # zim-modules/watchman-env/init.zsh from the mapping (one
    # don't-stomp-per-var guard; COMPFUZOR_ENV_OVERWRITE=1 forces) and a
    # `zmodule <abspath>` declaration, plus install-user-zimfw.sh to promote
    # it into the zim host. No bespoke script, no block-in-file.
    ZIM_MODULES:
      - name: watchman-env
        phase: tools
        env:
          WATCHMAN_SOCK: "{{VAR}}/sock"
          WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    # Root guard config — see header. Emitted at {{ETC}}/watchman.json and
    # read by the daemon via $WATCHMAN_CONFIG_FILE. Restart the service to
    # pick up changes (watchman reads global config only at startup; existing
    # roots are NOT re-validated, only new watch-project calls are gated).
    # Note: `root_files` + `enforce_root_files` are global-scope (read from
    # the global config); `ignore_dirs` is local-scope (per-root) per the
    # config.md scoping table — kept here for documentation and any future
    # watchman version that honors it globally, but the runtime effect today
    # is that build trees are NOT globally ignored. Compile-time `ignore_vcs`
    # defaults still skip .git/.hg/.jj during crawl.
    ROOT_GUARD:
      root_files: [".git", ".hg", ".jj"]
      enforce_root_files: true
      ignore_dirs:
        - node_modules
        - target
        - .build
        - build
        - dist
        - ".next"
        - ".cache"
        - ".turbo"
        - ".venv"
        - venv
        - __pycache__
        - ".tox"
        - ".mypy_cache"
        - ".pytest_cache"
  tasks:
    - import_tasks: tasks/compfuzor.includes

    - name: "Watchman root guard: emit config to {{ETC}}/watchman.json"
      copy:
        dest: "{{ETC}}/watchman.json"
        content: "{{ROOT_GUARD | to_nice_json}}\n"
        mode: "0644"
      when: not ROOT_GUARD_BYPASS|default(False)
      notify: restart watchman-main
  handlers:
    - name: restart watchman-main
      systemd:
        name: watchman-main
        scope: user
        daemon_reload: yes
        state: restarted
