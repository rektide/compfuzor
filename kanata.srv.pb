---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: main
    # kanata: the maintained successor to interception-tools (Debian
    # removed the latter from sid 2026-06-26). One daemon replaces the
    # whole udevmon | intercept | caps2esc | uinput pipeline; deployed on
    # workhorse 2026-09-30, displacing interception-tools-main.service
    # (whose trixie packages ride the debian-stable pin-100 backstop).
    PKGS:
      - kanata
    SYSTEMD_UNITS:
      Description: kanata -- advanced software keyboard remapper
      Documentation: https://github.com/jtroo/kanata
      Wants: systemd-udev-settle.service
      After: systemd-udev-settle.service
    SYSTEMD_SERVICES:
      Type: simple
      ExecStart: /usr/bin/kanata -c {{ETC}}/kanata.kbd
      Restart: on-failure
      RestartSec: "3"
    SYSTEMD_INSTALLS:
      WantedBy: multi-user.target
    ETC_FILES:
      - name: kanata.kbd
        content: |
          (defcfg
            process-unmapped-keys yes
          )

          (defsrc
            caps
          )

          (deflayer base
            ;; caps2esc: tap = escape, hold = left control
            (tap-hold 100 100 esc lctl)
          )
  tasks:
    - import_tasks: tasks/compfuzor.includes
