---
# kinesis.etc.pb — systemd .mount/.automount pair for the Kinesis Freestyle
# Edge RGB v-drive (SmartSet configuration volume) at /mnt/kinesis.
#
# Device evidence (2026-10-01, this host):
#   lsusb  29ea:0103 Kinesis Corporation Freestyle Edge RGB Keyboard
#   block  /dev/sde, 4 MB whole-disk vfat, no partition table — the v-drive
#          image on the keyboard's AT45DB DataFlash (udev ID_SERIAL
#          ATMEL_AT45DBX_Data_Fla_264575131106)
#   label  FS_EDGE_RGB    uuid 8C17-BD69
# The v-drive was already active when surveyed: the keyboard exposes the
# mass-storage LUN without any chord press. (sdc/sdd "MassStorageClass"
# 05e3:0749 are a Genesys SD-card reader's empty slots; the 1b8f:0303
# MA LABS MassStorage device is unrelated hardware.)
#
# WHAT defaults to the by-id path: the DataFlash chip serial pins the mount
# to this exact keyboard. The vfat uuid/label travel with the firmware
# image and are likely identical across every Freestyle Edge RGB — they
# identify the model, not the unit. Override with
#   -e what=/dev/disk/by-uuid/8C17-BD69
# to follow the image instead (survives keyboard replacement, loses
# per-unit disambiguation).
#
#   ansible-playbook -i 'localhost,' -c local kinesis.etc.pb
#   ls /mnt/kinesis    # any access triggers the mount
#
# The .automount is enabled and started; the .mount is link-only (systemd
# mounts it on demand when the automount path is accessed). Short idle
# timeout releases the volume so the keyboard can be unplugged without a
# busy filesystem; the next access re-triggers instantly. This playbook
# declares the mount machinery only — nothing on the volume is read or
# written here, and there is deliberately no unmount/cleanup logic.
#
# Write-protect note: the v-drive LUN's WP state is firmware-toggled and
# does not follow the block device (observed: mount(8) fell back to ro
# with "source write-protected" during a WP-on window, while
# `blockdev --getro` reported 0 both before and after). A mount that
# lands ro self-heals — the idle timeout releases it and the next access
# remounts at whatever WP state the keyboard then presents — or flip a
# live mount directly with `sudo mount -o remount,rw /mnt/kinesis`.
#
# Vars (optional, -e overrides):
#   what        mount source (default by-id path above)
#   where       mountpoint (default /mnt/kinesis)
#   uid/gid     vfat ownership (default: the run-as user)
#   mount_opts  appended to Options
#   idle        automount TimeoutIdleSec (default 1min)
- hosts: all
  vars:
    TYPE: kinesis
    WHAT: "{{what|default('/dev/disk/by-id/usb-ATMEL_AT45DBX_Data_Fla_264575131106-0:0')}}"
    WHERE: "{{where|default('/mnt/kinesis')}}"
    UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ WHERE) }}"
    MOUNT_UID: "{{uid|default(ansible_user_uid)}}"
    MOUNT_GID: "{{gid|default(ansible_user_gid)}}"
    MOUNT_OPTS: "uid={{MOUNT_UID}},gid={{MOUNT_GID}},umask=022,flush{{ ',' ~ mount_opts if mount_opts is defined else '' }}"
    SYSTEMD_ROOTS:
      - KINESIS_MOUNT
      - KINESIS_AUTOMOUNT
    KINESIS_MOUNT:
      SYSTEMD_MOUNT: "{{UNIT}}"
      # .mount units never enable directly; the automount pulls it in on demand.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "kinesis v-drive (Freestyle Edge RGB SmartSet volume) on {{WHERE}}"
      SYSTEMD_MOUNTS:
        comments: |
          What= is the by-id path (DataFlash chip serial) so the mount pins
          to this keyboard, not to any Freestyle Edge v-drive image. See
          kinesis.etc.pb header for the by-uuid alternative.
        What: "{{WHAT}}"
        Where: "{{WHERE}}"
        Type: vfat
        Options: "{{MOUNT_OPTS}}"
        TimeoutSec: 30
    KINESIS_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{UNIT}}"
      SYSTEMD_UNITS:
        Description: "kinesis v-drive lazy mount {{WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('1min')}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
