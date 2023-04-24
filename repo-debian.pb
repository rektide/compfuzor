---
- hosts: all
  vars:
    TYPE: debian
    INSTANCE: "{{APT_DISTRIBUTION|default(APT_DEFAULT_DISTRIBUTION)}}"
    # above default 500
    APT_REPO: "{{APT_DEFAULT_MIRROR}}"
    APT_PIN: "release n={{INSTANCE}}"
    APT_PIN_PRIORITY: 600
    APT_SOURCELIST: "{{NAME}}"
    APT_COMPONENTS:
      - main
      - non-free
      - contrib
    APT_TRUST: False
  tasks:
    - include: tasks/compfuzor/apt.tasks
