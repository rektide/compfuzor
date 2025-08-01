---
- hosts: all
  vars:
    TYPE: overlay
    INSTANCE: usr-share-fonts
    path: "/{{INSTANCE|replace('-', '/')}}"
    lower: "{{path}}"
    #upper: /home/.steamos/offload{{path}}
    upper: /var/lib/overlays{{path}}
    DIRS:
      - "{{upper}}/work"
      - "{{upper}}/upper"
    SYSTEMD_TYPE: mount
    SYSTEMD_MOUNT: "{{INSTANCE}}"
    SYSTEMD_WHAT: overlay
    SYSTEMD_WHERE: "{{lower}}"
    SYSTEMD_MOUNT_TYPE: overlay
    SYSTEMD_MOUNT_OPTIONS: "lowerdir={{lower}},upperdir={{upper}}/upper,workdir={{upper}}/work"
    SYSTEMD_WANTED_BY: steamos-offload.target
    ENV:
      - upper
      - lower
    BINS:
      - name: pretransfer.sh
        exec: |
          sudo mkdir -p $UPPER/upper $UPPER/work
          sudo rsync -a ${V+-v} $LOWER/ $UPPER/upper/
  tasks:
    - import_tasks: tasks/compfuzor.includes
