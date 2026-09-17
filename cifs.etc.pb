---
# cifs.etc.pb — systemd .mount/.automount units for SMB shares.
#
# Replaces the ancient Ansible-1.x automount-cifs.pb and fstab
# x-systemd.automount lines: one deployment per share, units owned by
# compfuzor under /etc/opt, linked into /etc/systemd/system by the generated
# install scripts.
#
#   ansible-playbook -i 'localhost,' -c local cifs.etc.pb
#   ansible-playbook -i 'localhost,' -c local cifs.etc.pb -e INSTANCE=x1 -e srv=xone
#
# INSTANCE is the share name on SRV; the unit basename is systemd-escaped
# from WHERE (/mnt/bitblaster -> mnt-bitblaster.{mount,automount}). The
# .automount is enabled and started; the .mount is link-only (systemd mounts
# it on demand when the automount path is accessed).
#
# SMB3.1.1 POSIX extensions (`posix` below) give native symlinks and real
# uid/gid/mode round-trip when the server allows them (samba.pb: "smb3 unix
# extensions"); otherwise the mount degrades to nounix forced modes.
#
# Vars (optional, -e overrides):
#   srv          server hostname (default nanomachine)
#   where        mountpoint (default /mnt/INSTANCE)
#   credentials  mount(8) credentials file (default: the existing
#                /root/.config/smb/nano used by the fstab line this replaces)
#   mount_opts   appended to Options
#   idle         automount TimeoutIdleSec (default 15min)
- hosts: all
  vars:
    TYPE: cifs
    INSTANCE: bitblaster
    SRV: "{{srv|default('nanomachine')}}"
    WHAT: "//{{SRV}}/{{INSTANCE}}"
    WHERE: "{{where|default('/mnt/' + INSTANCE)}}"
    CREDENTIALS: "{{credentials|default('/root/.config/smb/nano')}}"
    UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ WHERE) }}"
    # WARNING:nostrictsync!
    # WARNING idsfromsid
    # WARNING uid=1000, not cifs.idmap
    # not set: `fsc` caching, `compress` experimental, `persistenthandles`, `cache=loose`, `nosetuids`
    MOUNT_OPTS: "uid=1000,gid=staff,actimeo=10,max_cached_dirs=1024,max_channels=4,resilienthandles,echo_interval=20,nostrictsync,credentials={{CREDENTIALS}},vers=3.1.1,posix,iocharset=utf8,soft{{ ',' ~ mount_opts if mount_opts is defined else '' }}"
    SYSTEMD_ROOTS:
      - CIFS_MOUNT
      - CIFS_AUTOMOUNT
    CIFS_MOUNT:
      SYSTEMD_MOUNT: "{{UNIT}}"
      # .mount units never enable directly; the automount pulls it in on demand.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "cifs {{WHAT}} on {{WHERE}}"
        After: network-online.target
        Wants: network-online.target
      SYSTEMD_MOUNTS:
        What: "{{WHAT}}"
        Where: "{{WHERE}}"
        Type: cifs
        Options: "{{MOUNT_OPTS}}"
    CIFS_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{UNIT}}"
      SYSTEMD_UNITS:
        Description: "cifs automount {{WHAT}} on {{WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('15min')}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
