---
- hosts: all
  vars:
    TYPE: debian
    INSTANCE: "{{APT_DEFAULT_DISTRIBUTION}}"
    # above default 500
    APT:
      URIs: "{{APT_DEFAULT_MIRROR}}"
      Suites: "{{INSTANCE}}"
      Components: [main, non-free, contrib, non-free-firmware]
    APT_PREFS:
      Pin: "release n={{INSTANCE}}"
      Pin-Priority: 600
    APT_SOURCELIST: "{{NAME}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: etc
