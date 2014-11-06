---
- hosts: all
  gather_facts: False
  vars_files:
  - vars/common.user.vars
  - vars/xdg.vars
  vars:
    USERMODE: True
    VOLUMES:
      "{{LOCAL_DIR}}"
      "{{OPTS_DIR}}"
      "{{SRVS_DIR}}"
      "{{VARS_DIR}}"
      "{{SRCS_DIR}}"
      "{{LOGS_DIR}}"
      "{{CACHES_DIR}}"
      "{{ETCS_DIR}}"
      "{{MEDIAS_DIR}}"
      "{{XDG_DOCUMENTS_DIR}}"
      "{{XDG_DOWNLOAD_DIR}}"
      "{{XDG_MUSIC_DIR}}"
      "{{XDG_PICTURES_DIR}}"
      "{{XDG_BOOKS_DIR}}"
      "{{XDG_PUBLICSHARE_DIR}}"
      "{{XDG_VIDEOS_DIR}}"
  tasks:
  - 
