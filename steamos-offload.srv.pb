---
- hosts: all
  vars:
    TYPE: steamos-offload
    INSTANCE: 'usr-local-src'
    SYSTEMD_WHAT: "/home/.steamos/offload{{path}}"
    SYSTEMD_WHERE: "{{path}}"
    #SYSTEMD_WHAT: /%s
    #SYSTEMD_WHERE: /home/.steamos/offload/%s
    SYSTEMD_TYPE: mount
    SYSTEMD_MOUNT: "{{INSTANCE|replace('/', '-')}}"
    SYSTEMD_MOUNT_TYPE: none
    SYSTEMD_MOUNT_OPTIONS: bind
    SYSTEMD_WANTED_BY: steamos-offload.target
    ENV:
      - SYSTEMD_WHAT
      - SYSTEMD_WHERE
    path: "/{{INSTANCE|replace('-', '/')}}"
    ETC_DIR: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
