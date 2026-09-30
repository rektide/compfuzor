---
- hosts: all
  vars:
    TYPE: keyd
    INSTANCE: main
    # keyd playbook -- STAGED ONLY, not deployed on workhorse (kanata won
    # the interception-tools migration 2026-09-30). Deploy when wanted:
    # render, then `sudo bash {{DIR}}/bin/install.sh` (config link + pkgs)
    # plus `sudo systemctl enable --now keyd` -- keyd uses its packaged
    # keyd.service unit, so no SYSTEMD_* declarations here.
    PKGS:
      - keyd
    # keyd reads only /etc/keyd/*.conf (no config-path flag), so the
    # config is staged in ETC and linked into place
    LINKS:
      - src: "{{ETC}}/app.conf"
        dest: /etc/keyd/app.conf
        scope: system
        policy: replace
    ETC_FILES:
      - name: app.conf
        content: |
          [ids]
          *

          [main]
          # caps2esc: hold = control, tap = escape
          caps = overload(control, esc)
  tasks:
    - import_tasks: tasks/compfuzor.includes
