---
- hosts: all
  vars:
    REPO: https://github.com/ShadowBlip/InputPlumber
    RUST: True
    PKGS:
      - libiio-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
