---
- hosts: all
  vars:
    TYPE: spaceship
    INSTANCE: main
    USERMODE: True
    ENV:
      SPACESHIP_CONFIG: "{{DIR}}/etc/spaceship.zsh"
    ETC_FILES:
      - name: spaceship.zsh
        content: ""
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          {{DIR}}/bin/config.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
