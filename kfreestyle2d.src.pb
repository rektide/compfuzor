---
# kfreestyle2d -- Kinesis Freestyle 2 userspace driver (whereswaldon/kfreestyle2d)
#
# Single C file (k.c, c99 + make): reads the keyboard's Fn/multimedia
# hidraw collection (USB 058f:9410, interface 01 -- hid-generic does not
# claim it) and republishes those keys through uinput.
#
# Upstream's `make install` runs a *system* service as a dedicated
# `uinput` user and starts it from a udev RUN+= hook. Per the upstream
# SECURITY NOTICE ("should not run as root"), this deployment instead
# runs it as a user service gated by a user path unit, so nothing runs
# while the keyboard is detached and it self-starts whenever
# /dev/kfreestyle2-fn appears (plug-in, or session start with it already
# attached -- SYSTEMD_USER_WANTS from udev only fires at device
# activation and misses late logins; the path unit covers both).
#
#   udev 71-kfreestyle2d.rules -> /dev/kfreestyle2-fn symlink + access
#   kfreestyle2d.path  (user)  -> starts kfreestyle2d.service on appear
#   kfreestyle2d.service (user)-> /usr/local/bin/kfreestyle2d /dev/kfreestyle2-fn
#
# Deploy after render:
#   sudo bash {{DIR}}/bin/install.sh     # pkgs + udev rule (system scope)
#   bash {{DIR}}/bin/install-user.sh     # units + enable kfreestyle2d.path
#   sudo bash {{DIR}}/bin/apply-udev.sh  # udevadm reload + hidraw trigger
# The keyboard does not need to be attached for any of the above; the
# path unit starts the service whenever it shows up. One Freestyle 2 per
# machine (upstream limitation).
#
# Iterate without side effects: add -e MODULES_BYPASS=True.
- hosts: all
  vars:
    TYPE: kfreestyle2d
    INSTANCE: git
    REPO: https://github.com/whereswaldon/kfreestyle2d
    # c99 one-file build. No MAKE: True -- the make subsystem's install
    # lane would run upstream `make install`, which writes /etc/systemd,
    # /etc/udev, appends /etc/modules, and groupadds a system user.
    PKGS:
      - build-essential
    # uinput at boot (it also autoloads on open via MODULE_ALIAS_MISCDEV;
    # this keeps the guarantee explicit). Render needs sudo or
    # MODULES_BYPASS=True.
    MODULES:
      - uinput
    BINS:
      - name: build.sh
        basedir: repo
        run: true
        exec: |
          make -j"$(nproc)"
      - name: install-bin.sh
        basedir: repo
        run: true
        exec: |
          ln -sfv "$(pwd)/kfreestyle2d" "$GLOBAL_BINS_DIR/kfreestyle2d"
      - name: apply-udev.sh
        content: |
          sudo udevadm control --reload-rules
          sudo udevadm trigger --subsystem-match=hidraw --action=add
    ETC_FILES:
      # Numbered 71- not upstream's 99-: the uaccess builtin that
      # consumes TAG+="uaccess" runs from 73-seat-late.rules, so a
      # 99- file tagging uaccess would never take effect. This rule
      # only matches sysfs attrs, so it has no ordering needs before 71.
      - name: 71-kfreestyle2d.rules
        mode: "0644"
        content: |
          # Kinesis Freestyle 2 (058f:9410): interface 01 is the
          # Fn/multimedia collection. Adapted from upstream's
          # 99-kfreestyle2d.rules.template: GROUP=input + uaccess for the
          # seated user instead of upstream's dedicated `uinput`
          # user/group (this deployment runs kfreestyle2d as a user
          # service), plus the stable symlink the user path unit watches.
          KERNEL=="hidraw[0-9]*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="058f", ATTRS{idProduct}=="9410", ATTRS{bInterfaceNumber}=="01", MODE="0660", GROUP="input", TAG+="uaccess", SYMLINK+="kfreestyle2-fn"
          # /dev/uinput write access for the user service (mirrors the
          # kanata package's 50-kanata-uinput.rules; static_node keeps
          # the node present from early boot).
          KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
    LINKS:
      - src: "{{ETC}}/71-kfreestyle2d.rules"
        dest: /etc/udev/rules.d/71-kfreestyle2d.rules
        scope: system
        policy: replace
    # user-scope units, activated by device appearance rather than boot
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_USERMODE: True
    # Root order is the install order inside install-systemd-user.sh:
    # service (link-only) must land before the path unit enables+starts,
    # else the path start aborts with "unit to trigger not loaded" and
    # the compositor stops before the service installer runs.
    SYSTEMD_ROOTS: [kfreestyle2dService, kfreestyle2dPath]
    kfreestyle2dPath:
      SYSTEMD_PATH: kfreestyle2d
      SYSTEMD_UNITS:
        Description: Watch for the Kinesis Freestyle 2 Fn-key device
      SYSTEMD_PATHS:
        PathExists: /dev/kfreestyle2-fn
      SYSTEMD_INSTALLS:
        WantedBy: paths.target
    kfreestyle2dService:
      SYSTEMD_SERVICE: kfreestyle2d
      # link-only: the path unit owns activation (enable --now would
      # fail while the keyboard is detached)
      SYSTEMD_ENABLE: False
      SYSTEMD_UNITS:
        Description: Kinesis Freestyle 2 Fn-key userspace driver
        Documentation: https://github.com/whereswaldon/kfreestyle2d
        ConditionPathExists: /dev/kfreestyle2-fn
      SYSTEMD_SERVICES:
        ExecStart: "{{GLOBAL_BINS_DIR}}/kfreestyle2d /dev/kfreestyle2-fn"
        Restart: on-failure
        RestartSec: 2
  tasks:
    - import_tasks: tasks/compfuzor.includes
