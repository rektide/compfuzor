---
- hosts: all
  vars:
    TYPE: losetup-mount
    INSTANCE: mnt-loop
    SYSTEMD_MOUNT: "{{INSTANCE|replace('\\-', '\\x2d')}}"
    #SYSTEMD_TYPE: mount
    #SYSTEMD_SERVICE: True
    LOOP_NUM: "{{loop_num|default(1999)}}"
    WHERE:  "/{{where|default(INSTANCE)|regex_replace('([^\\\\])-', '\\1/')|replace('\\-', '-')}}"
    MOUNT_TYPE: "{{mount_type|default('btrfs')}}"
    OPTIONS: "{{option|default('subvol=' + INSTANCE)}}"
    SYSTEMD_UNITS:
      Description: Mount loop devices
      DefaultDependencies: no
      Conflicts: umount.target
      Before: local-fs.target
      After: losetup@{{LOOP_NUM}}.service
      Requires: losetup@{{LOOP_NUM}}.service
    SYSTEMD_MOUNTS:
      What: "/dev/loop{{LOOP_NUM}}"
      Where: "{{WHERE}}"
      Type: "{{MOUNT_TYPE}}"
      Options: "subvol={{INSTANCE}}"
    SYSTEMD_INSTALLS:
      WantedBy: local-fs.target
      Also: systemd-udevd.service
    ENV:
      LOOP_NAME: "{{LOOP_NAME|default(INSTANCE)}}"
      LOOP_NUM: "{{LOOP_NUM|default(1999)}}"
      LOOP_IMG: "{{LOOP_IMG|default(DIR+'/var/img')}}"
      MKFS: "{{MKFS|default('mkfs.btrfs --label ${LOOP_NAME}')}}"
      SIZE_KB: "{{SIZE_M|default(1024*1024*16)}}"
    ETC_DIR: True
    VAR_DIR: True
  tasks:
    #- fail:
    #    msg: "{{WHERE}}"
    - import_tasks: tasks/compfuzor.includes
