---
- hosts: all
  vars:
    TYPE: waydroid
    INSTANCE: main
    APT_REPO: https://repo.waydro.id
    APT_TRUSTED: waydroid
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
