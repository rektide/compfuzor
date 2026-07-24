---
- hosts: all
  vars:
    TYPE: gdm-no-suspend
    INSTANCE: main
    PKGS:
      - crudini
    ENV:
      dest: /etc/gdm3/greeter.dconf-defaults
    ETC_FILES:
      - name: no-suspend.conf
        content: |
          [org/gnome/settings-daemon/plugins/power]
          sleep-inactive-ac-type = 'nothing'
          sleep-inactive-battery-type = 'nothing'
          sleep-inactive-ac-timeout = 0
          sleep-inactive-battery-timeout = 0

          [org/gnome/desktop/session]
          idle-delay = uint32 0
    BINS:
      - name: install-dconf.sh
        content: |
          sudo crudini --merge "$DEST" < "$DIR/etc/no-suspend.conf"
          sudo systemctl reload gdm
  tasks:
    - import_tasks: tasks/compfuzor.includes
