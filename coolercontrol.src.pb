---
- hosts: all
  vars:
    TYPE: coolercontrol
    INSTANCE: git
    REPO: https://gitlab.com/coolercontrol/coolercontrol
    PKGS:
      - qt6-webengine-dev-tools
      - qt6-webengine-dev
    BINS:
      - name: build.sh
        exec: |
          make build build-ui
  tasks:
    - import_tasks: tasks/compfuzor.includes
