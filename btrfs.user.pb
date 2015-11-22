---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/xdg.vars
  vars:
    TYPE: btrfs
    INSTANCE: main
    USERMODE: True
    LOCAL_DIR: "${HOME}/.local"
    MEDIAS_DIR: "{{ PREFIX_DIR+'media' if PREFIX_DIR is defined else '~/media' }}"
    SUBVOLUMES:
    - "{{LOCAL_DIR}}"
    - "{{MEDIAS_DIR}}"
    - "{{CACHES_DIR}}"
    - "{{XDG_DOCUMENTS_DIR}}"
    - "{{XDG_DOWNLOAD_DIR}}"
    - "{{XDG_MUSIC_DIR}}"
    - "{{XDG_PICTURES_DIR}}"
    - "{{XDG_BOOKS_DIR}}"
    - "{{XDG_PUBLICSHARE_DIR}}"
    - "{{XDG_VIDEOS_DIR}}"
    BINS:
    - subvolumize.sh
    - rootfs.sh
    - test-subvol.sh
  tasks:
  - include: tasks/compfuzor.includes type="opt"
