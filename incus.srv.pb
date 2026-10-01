---
# Incus daemon bring-up: storage pool, network bridge, default profile.
# ASSUMES incus.opt.pb (packages + access); renders no units of its own --
# the deb ships incus.service/incus-user.service, which we only ensure.
#
# Everything is guarded + idempotent so re-running never reconfigures:
#   storage pool `default` (btrfs -- root fs is btrfs, so the pool is a
#     subvolume and containers/VMs snapshot cheaply)
#   network incusbr0 (defaults: NAT'd ipv4, no ipv6)
#   default profile: root disk on `default`, eth0 on incusbr0
- hosts: all
  vars:
    TYPE: incus
    INSTANCE: init
    BINS:
      - name: install.sh
        exec: |
          set -e

          # deb units: enabled by apt's postinst; ensure for the re-image case
          sudo systemctl enable --now incus.service incus-user.service

          # wait for the local daemon socket (fresh clusters take a moment)
          for i in $(seq 1 30); do
            sudo incus storage list >/dev/null 2>&1 && break
            sleep 1
          done
          sudo incus storage list >/dev/null 2>&1 || { echo "incus daemon not answering" >&2; exit 1; }

          # storage: btrfs subvolume pool on the btrfs root fs
          sudo incus storage list --format csv | cut -d, -f1 | grep -qx default || \
            sudo incus storage create default btrfs

          # network: NAT bridge with upstream defaults
          sudo incus network show incusbr0 >/dev/null 2>&1 || \
            sudo incus network create incusbr0

          # default profile: root disk + eth0 (mirrors `incus admin init --auto`)
          sudo incus profile device get default root pool >/dev/null 2>&1 || \
            sudo incus profile device add default root disk path=/ pool=default
          sudo incus profile device get default eth0 network >/dev/null 2>&1 || \
            sudo incus profile device add default eth0 nic name=eth0 network=incusbr0

          echo
          sudo incus storage list
          sudo incus profile device show default
    README: |
      # Incus init

      Daemon-side initialization for incus.opt.pb's install: storage,
      network, default profile. Re-runnable (every step is guarded).

          ansible-playbook -i 'localhost,' -c local incus.srv.pb
          sudo bash {{DIR}}/bin/install.sh

      Afterwards (`newgrp incus-admin` or re-login for socket access):

          incus launch images:debian/13 c1        # container
          incus launch images:debian/13 v1 --vm   # VM via /dev/kvm
          incus snapshot c1 snap0                 # btrfs-backed, cheap
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: srv

