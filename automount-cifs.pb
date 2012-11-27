---
- hosts: all
  sudo: True
  vars_files:
  - private/automount-cifs/xone.downloads
  - private/automount-cifs/xone.x1
  - private/automount-cifs/map
  tasks:
  - template: src=files/automount-cifs/srv.automount dest=/etc/systemd/system/mnt-smb-${item.srv}-${item.share}.automount
    with_items: ${remotes}
    register: has_automount
  - template: src=files/automount-cifs/srv.mount dest=/etc/systemd/system/mnt-smb-${item.srv}-${item.share}.mount
    with_items: ${remotes}
    register: has_mount
  - template: src=files/automount-cifs/srv.creds dest=/root/.cifscred-${item.srv}-${item.share} mode=0400
    with_items: ${remotes}
    register: has_creds
  - shell: systemctl daemon-reload
    only_if: ${has_mount.changed} or ${has_automount.changed}
  - shell: systemctl enable mnt-smb-${item.srv}-${item.share}.automount
    with_items: ${remotes}
    only_if: ${has_automount.changed}
  - shell: systemctl reload-or-restart mnt-smb-${item.srv}-${item.share}.automount
    with_items: ${remotes}
    only_if: ${has_automount.changed}
