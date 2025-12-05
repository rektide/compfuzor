---
- hosts: all
  vars:
    TYPE: mako
    INSTANCE: main
    ETC_FILES:
      - name: config.yaml
        yaml:
          default-timeout: 5
    BINS:
      - name: yaml2args
        src: ../yaml2args
        raw: True
      - name: build-etc.sh
        run: True
        content: |
          ./bin/yaml2args --ini etc/config.yaml > etc/config
      - name: install-user.sh
        content: |
          mkdir -p $HOME/.config/mako
          ln -sfv "$(pwd)/etc/config" $HOME/.config/mako
  tasks:
    - import_tasks: tasks/compfuzor.includes

