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
    #
    # Uses the PACKAGED kanata.service (the kanata package auto-enables it
    # on install, so a second own unit just fights it): config is staged
    # in ETC and linked over /etc/kanata/config.kbd -- the keyd pattern.
    PKGS:
      - kanata
    # the packaged kanata.service runs as its own (dynamic) user: the ETC
    # dir and config must be world-traversable/readable (0770/0660 default
    # DIRMODE/FILEMODE block it -- same lesson as apt-cacher-rs)
    ETC_PROP:
      mode: "0755"
    LINKS:
      - src: "{{ETC}}/kanata.kbd"
        dest: /etc/kanata/config.kbd
        scope: system
        policy: replace
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
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
