---
- hosts: all
  become: True
  tags:
  - packages
  - root
  vars:
    NAME: debian-experimental
    APT_REPO: "{{APT_DEFAULT_MIRROR}}"
    APT_DISTRIBUTION: experimental
    APT_PIN: "release a=experimental"
    APT_PIN_PRIORITY: 200
    APT_TRUST: false # assume we have debian keys
    APT_COMPONENTS:
    - main
    - contrib
    - non-free
  tasks:
  - import_tasks: tasks/compfuzor/apt.tasks
