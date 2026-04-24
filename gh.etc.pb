---
- hosts: all
  vars:
    USERMODE: True
    ENV: True
    ETC_FILES:
      - name: config.yml
        yaml:
          telemetry: disabled
    BINS:
      - name: install-user.sh
        exec: |
          mkdir -p ~/.config/gh
          block-in-file -n "$NAME" -i "$DIR/etc/config.yml" -o ~/.config/gh/config.yml
  tasks:
    - import_tasks: tasks/compfuzor.includes
