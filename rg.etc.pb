---
- hosts: all
  vars:
    TYPE: rg
    INSTANCE: main
    ENV: {}
    ETC_FILES:
      - name: rgconfig
        content: |
          --smart-case
      - name: rgconfig.sh
        content: |
          export RIPGREP_CONFIG_PATH=${DIR}/etc/rgconfig
    BINS:
      - name: install-user.sh
        basedir: False
        content: |
          cat {{DIR}}/etc/rgconfig.sh | envsubst | block-in-file -o ~/.zshrc
  tasks:
    - import_tasks: tasks/compfuzor.includes
