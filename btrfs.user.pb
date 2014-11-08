---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.user.vars
  - vars/xdg.vars
  vars:
    USERMODE: True
    SUBVOLUMES:
    - "{{LOCAL_DIR}}"
    - "{{OPTS_DIR}}"
    - "{{SRVS_DIR}}"
    - "{{VARS_DIR}}"
    - "{{SRCS_DIR}}"
    - "{{LOGS_DIR}}"
    - "{{ETCS_DIR}}"
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
      name: subvolumeize.sh
  tasks:
  #- include: tasks/compfuzor.includes type="opt"
