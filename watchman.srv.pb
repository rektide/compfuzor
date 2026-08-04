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
# A bare `watchman watch-project ~/src` (or any huge tree) exhausts inotify
# watches → poison state → jj (which uses watchman as fsmonitor) hangs on every
# status/commit. The durable fix is a global root_files guard in the daemon's
# config: with `enforce_root_files: true` + `root_files: [".git",".hg",".jj"]`,
# watchman walks UP from the requested path to the nearest dir containing a
# marker, refusing if none exists. So `watch-project ~/src/<repo>` resolves to
# <repo> (has .git); `watch-project ~/src` is refused outright.
#
# HOW THE CONFIG REACHES THE DAEMON (fully user-mode, no /etc writes):
# Watchman reads `$WATCHMAN_CONFIG_FILE` (WatchmanConfig.cpp:28, overrides the
# compile-time `/etc/watchman.json`). We emit the config at {{ETC}}/watchman.json
# and set the env var on the unit. No sudo.
#
# CLI→DAEMON ROUTING (the subtle part — was a multi-hour misdiagnosis):
# The C++ `watchman` CLI **ignores `$WATCHMAN_SOCK`** — only python/node/rust
# clients honor it (Connect.cpp:24, sockname.cpp:25, UserDir.cpp:195). The CLI
# computes its socket from the compile-time `WATCHMAN_STATE_DIR` macro:
# `<STATE_DIR>/<username>-state/sock`. If that socket has no listener, the CLI
# auto-spawns a fresh ad-hoc daemon (main.cpp:955) that inherits the CLI's env
# (which, for non-interactive contexts, lacks `WATCHMAN_CONFIG_FILE` → no guard).
# Rather than rebuild (a getdeps dependency nightmare), we **symlink the CLI's
# compile-time default `<user>-state` path to our managed {{VAR}} dir**. Then
# every bare `watchman` invocation connects through the symlink to our managed
# daemon, which has the guard loaded. Single daemon, no spawn, no env gymnastics.
# The SYSTEMD_ENV / ZIM_MODULES wiring below is belt-and-suspenders for
# python/node/rust clients (which DO honor $WATCHMAN_SOCK).
- hosts: all
  vars:
    TYPE: watchman
    USERMODE: True

    VAR_DIR: True
    VAR_FILES:
      - name: state
        content: "{}"

    # Watchman refuses to use a state dir that's group/other-writable (security
    # check: "the permissions on <dir> allow others to write to it"). Enforce
    # 0700 on {{VAR}} to satisfy this.
    VAR_MODE: "0700"

    # The compile-time WATCHMAN_STATE_DIR that `watchman.src.pb`'s getdeps build
    # baked into the binary (see scratch/build/watchman/watchman/config.h).
    # The bare CLI computes its default socket as
    # <WATCHMAN_DEFAULT_STATE_DIR>/<username>-state/sock. We symlink that path
    # to {{VAR}} below so the CLI connects to our daemon. Override here if the
    # binary is rebuilt with a different -DWATCHMAN_STATE_DIR.
    WATCHMAN_DEFAULT_STATE_DIR: /usr/local/src/watchman-git/watchman/var/run/watchman

    SYSTEMD_ENV:
      WATCHMAN_SOCK: "{{VAR}}/sock"
      WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

    SYSTEMD_SERVICES:
      ExecStart: "watchman --persistent --foreground --statefile={{VAR}}/state --pidfile={{VAR}}/pid --sockname={{VAR}}/sock --logfile={{VAR}}/log"
      Environment:
        - "WATCHMAN_CONFIG_FILE={{ETC}}/watchman.json"
      Restart: always
      RestartSec: "2s"

    ZIM_MODULES:
      - name: watchman-env
        phase: tools
        env:
          WATCHMAN_SOCK: "{{VAR}}/sock"
          WATCHMAN_CONFIG_FILE: "{{ETC}}/watchman.json"

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

    - name: "Watchman CLI routing: get current username for <user>-state path"
      command: id -un
      register: _watchman_user
      changed_when: false
      when: not WATCHMAN_CLI_SYMLINK_BYPASS|default(False)

    - name: "Watchman CLI routing: ensure compile-time state dir parent exists"
      file:
        path: "{{WATCHMAN_DEFAULT_STATE_DIR}}"
        state: directory
        mode: "0755"
      when: not WATCHMAN_CLI_SYMLINK_BYPASS|default(False)

    - name: "Watchman CLI routing: symlink CLI default <user>-state → {{VAR}}"
      file:
        src: "{{VAR}}"
        dest: "{{WATCHMAN_DEFAULT_STATE_DIR}}/{{_watchman_user.stdout}}-state"
        state: link
        force: true
      when: not WATCHMAN_CLI_SYMLINK_BYPASS|default(False)
      notify: restart watchman-main
  handlers:
    - name: restart watchman-main
      systemd:
        name: watchman-main
        scope: user
        daemon_reload: yes
        state: restarted
