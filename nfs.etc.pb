---
# nfs.etc.pb — systemd .mount/.automount units for an NFS export.
#
# One deployment per mount, mirroring cifs.etc.pb: units owned by compfuzor
# under /etc/opt, linked into /etc/systemd/system by the generated install
# scripts (each install-unit.sh applies its own LINKS record through
# bin/links.mjs before enabling). The .automount is enabled and started;
# the .mount is link-only (systemd mounts it on demand when the automount
# path is accessed), so no [Install] and no Alias are rendered for it —
# path unit aliases are illegal, and SYSTEMD_ALIAS: false opts the derived
# instance-suffix alias out for both units.
#
#   ansible-playbook -i 'localhost,' -c local nfs.etc.pb
#   ansible-playbook -i 'localhost,' -c local nfs.etc.pb \
#     -e INSTANCE=media -e srv=fileserver -e export_path=/srv/media
#
# Pair with nfs-export.srv.pb, which exports the server side
# (default export /srv/nfs-test on 127.0.0.1 for the INSTANCE=test pair).
#
# Vars (optional, -e overrides):
#   srv          server hostname/address (default 127.0.0.1)
#   export_path  exported path on the server (default /srv/nfs-<INSTANCE>)
#   where        mountpoint (default /mnt/nfs-<INSTANCE>; absolute, not /)
#   mount_opts   appended to Options
#   idle         automount TimeoutIdleSec (default 15min)
- hosts: all
  vars:
    TYPE: nfs
    INSTANCE: test
    SRV: "{{srv|default('127.0.0.1')}}"
    EXPORT_PATH: "{{export_path|default('/srv/nfs-' + INSTANCE)}}"
    WHAT: "{{SRV}}:{{EXPORT_PATH}}"
    WHERE: "{{where|default('/mnt/nfs-' + INSTANCE)}}"
    UNIT: "{{ lookup('pipe', 'systemd-escape --path ' ~ (WHERE|quote)) }}"
    # vers=4.2 pins the negotiation; tcp avoids UDP fragility, hard retries
    # instead of surfacing EIO, and _netdef.. _netdev defers the mount until
    # the network is up. Append knobs with mount_opts.
    MOUNT_OPTS: "vers=4.2,proto=tcp,hard,_netdev{{ (',' ~ mount_opts) if mount_opts|default('')|length else '' }}"
    SYSTEMD_ALIAS: false
    SYSTEMD_ROOTS:
      - NFS_MOUNT
      - NFS_AUTOMOUNT
    NFS_MOUNT:
      SYSTEMD_MOUNT: "{{UNIT}}"
      # .mount units never enable directly; the automount pulls it in on
      # demand when the automount path is accessed.
      SYSTEMD_ENABLE: false
      SYSTEMD_INSTALLS: false
      SYSTEMD_UNITS:
        Description: "nfs {{WHAT}} on {{WHERE}}"
        After: network-online.target
        Wants: network-online.target
      SYSTEMD_MOUNTS:
        What: "{{WHAT}}"
        Where: "{{WHERE}}"
        Type: nfs
        Options: "{{MOUNT_OPTS}}"
    NFS_AUTOMOUNT:
      SYSTEMD_AUTOMOUNT: "{{UNIT}}"
      SYSTEMD_UNITS:
        Description: "nfs automount {{WHAT}} on {{WHERE}}"
      SYSTEMD_AUTOMOUNTS:
        Where: "{{WHERE}}"
        DirectoryMode: "0755"
        TimeoutIdleSec: "{{idle|default('15min')}}"
      SYSTEMD_INSTALLS:
        WantedBy: multi-user.target
    PKGS: [nfs-common]
    ARCH_PKGS: [nfs-utils]
  pre_tasks:
    - name: "Compfuzor: kernel NFS requires the system scope"
      ansible.builtin.fail:
        msg: >-
          nfs: USERMODE is unsupported; NFS kernel mounts need the system
          scope. Re-run without USERMODE.
      when: USERMODE is deftruthy
    - name: "Compfuzor: validate the mount declaration"
      ansible.builtin.assert:
        that:
          - WHERE is match('^/')
          - WHERE | length > 1
          - WHERE is not match('[\s]')
          - EXPORT_PATH is match('^/')
          - EXPORT_PATH | length > 1
          - EXPORT_PATH is not match('[\s]')
          - SRV is match('^[A-Za-z0-9.\[\]:-]+$')
          - MOUNT_OPTS is match('^[A-Za-z0-9_.=,:@+-]+$')
        fail_msg: >-
          nfs: invalid declaration (srv={{ SRV }} export_path={{ EXPORT_PATH }}
          where={{ WHERE }} mount_opts={{ MOUNT_OPTS|default('') }}): paths
          must be absolute and not /, and every field must be free of
          whitespace so it cannot break the unit file or the escape lookup
        success_msg: "nfs: mount declaration validated"
  tasks:
    - import_tasks: tasks/compfuzor.includes
