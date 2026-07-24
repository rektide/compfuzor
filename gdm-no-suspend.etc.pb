---
- hosts: all
  vars:
    TYPE: gdm-no-suspend
    INSTANCE: main
    ENV:
      dest: /etc/dconf/db/gdm.d/00-no-suspend
    ETC_FILES:
      - name: 00-no-suspend
        content: |
          [org/gnome/settings-daemon/plugins/power]
          sleep-inactive-ac-type='nothing'
          sleep-inactive-battery-type='nothing'
          sleep-inactive-ac-timeout=0
          sleep-inactive-battery-timeout=0

          [org/gnome/desktop/session]
          idle-delay=uint32 0
    BINS:
      - name: install-dconf.sh
        content: |
          sudo mkdir -p "$(dirname "$DEST")"
          sudo ln -sfv "$DIR/etc/00-no-suspend" "$DEST"
          sudo dconf update
  tasks:
    - import_tasks: tasks/compfuzor.includes
