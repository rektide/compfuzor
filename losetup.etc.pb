---
- hosts: all
  vars:
    TYPE: losetup
    INSTANCE: "1999"
    SYSTEMD_SERVICE: "{{TYPE}}"
    SYSTEMD_INSTANCE: "{{INSTANCE}}"
    SYSTEMD_ENABLE: True
    SYSTEMD_CWD: False
    SYSTEMD_UNITS:
      Description: Setup loop devices
      DefaultDependencies: no
      Conflicts: umount.target
      Before: local-fs.target
      After: systemd-udevd.service home.mount
      Requires: systemd-udevd.service
    SYSTEMD_SERVICES:
      Type: oneshot
      ExecStart: "/sbin/losetup /dev/loop%I ${LOOP_IMG}"
      ExecStop: /sbin/losetup -d /dev/loop%I
      TimeoutSec: 60
      RemainAfterExit: yes
    SYSTEMD_INSTALLS:
      WantedBy: local-fs.target
      Also: systemd-udevd.service
    ENV:
      LOOP_NUM: "{{LOOP_NUM|default(INSTANCE)}}"
      LOOP_IMG: "{{LOOP_IMG|default(DIR+'/var/img')}}"
      MKFS: "{{MKFS|default('mkfs.btrfs --label ' + NAME)}}"
      SIZE_KB: "{{SIZE_M|default(1024*1024*16)}}"
    ETC_DIR: True
    VAR_DIR: True
    BINS:
      - name: "install-img-symlink.sh"
        basedir: False
        content: |
          [ -z "${1:-img}" ] && echo 'need img $1' >&2 && exit 1
          [ -e "$LOOP_IMG" ] && mv -v $LOOP_IMG ${LOOP_IMG}.backup-$(date --iso-8601=seconds)
          ln -sv $(readlink -e ${1:-img}) $LOOP_IMG
      - name: allocate-img.sh
        basedir: False
        content: |
          IMG=${1:-img}
          dd of=${IMG} bs=1k seek=${SIZE_KB} count=0 # create a 16G sparsefile
          ${MKFS} ${IMG}
      - name: install-service.sh
        content: |
          systemctl enable {{TYPE}}@{{INSTANCE}}.service
  tasks:
    - import_tasks: tasks/compfuzor.includes
