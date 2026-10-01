---
# Incus -- container + VM manager (LXD fork by its original author).
# Installs the Zabbly-built deb; ASSUMES zabbly.repo.pb has been rendered
# and installed (sudo bash /etc/opt/zabbly-incus-stable/bin/install.sh), or
# install-apt.sh below cannot resolve `incus` against the trixie suite.
#
# Daemon bring-up (storage pool, bridge, default profile) is a separate
# concern: incus.srv.pb. This playbook is just the host tooling: packages,
# KVM module, group membership.
#
# VMs: this host is a Ryzen 5800X with svm, but the kvm_amd module was never
# loaded (/dev/kvm absent). MODULES below fixes that persistently; the
# install bin also modprobes immediately so no reboot is required.
- hosts: all
  vars:
    TYPE: incus
    MODULES:
      - kvm_amd   # hardware VMs: qemu wants /dev/kvm (TCG fallback is slow)
    BINS:
      - name: install-access.sh
        exec: |
          # group membership: the incus unix socket is root:incus-admin 0660.
          # Takes effect on next login (or `newgrp incus-admin`).
          sudo usermod -aG incus-admin "{{ansible_user_id}}"
          # root subuid/subgid: incus's idmapped-mount paths don't strictly
          # need it, but classic shift/quota handling does; harmless if the
          # VFS-idmap path is taken instead.
          grep -q '^root:100000:65536$' /etc/subuid 2>/dev/null || \
            sudo usermod --add-subuids 100000-165535 root
          grep -q '^root:100000:65536$' /etc/subgid 2>/dev/null || \
            sudo usermod --add-subgids 100000-165535 root
          # make /dev/kvm exist now rather than after the next boot
          sudo modprobe kvm_amd || true
    PKGS:
      - incus   # pulls incus-client; incus-ui-canonical is optional (web UI)
    README: |
      # Incus

      Container + VM manager, from Zabbly's apt repo (zabbly.repo.pb).
      This playbook installs the host tooling; run incus.srv.pb afterwards
      to initialize the daemon (storage pool, network bridge, default
      profile).

      ## Run / iterate

          # assumes zabbly.repo.pb is rendered + installed
          ansible-playbook -i 'localhost,' -c local incus.opt.pb
          sudo bash {{DIR}}/bin/install.sh     # apt -> group/subuid -> kvm

      ## First steps

          incus list                          # empty; daemon talks via
                                              # /var/lib/incus/unix.socket
          # container:
          incus launch images:debian/13 c1
          # VM (kvm_amd module now loaded -- MODULES persists it):
          incus launch images:debian/13 v1 --vm

      Group membership from install-access.sh applies on next login; use
      `sudo incus ...` or `newgrp incus-admin` in the current shell.

      ## Locations

      | what          | where                                    |
      |---------------|------------------------------------------|
      | packages      | incus, incus-client (zabbly trixie repo) |
      | daemon units  | incus.service, incus-user.service (deb)  |
      | socket        | /var/lib/incus/unix.socket (incus-admin) |
      | daemon state  | /var/lib/incus (btrfs -> srv's btrfs pool)|
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt

