---
- hosts: all
  sudo: True
  vars_files:
  - private/sabnzbd.vars
  - vars/apt.vars
  handlers:
  - include: handlers.yaml
  tasks:
  - apt: state=$APT_INSTALL pkg=sabnzbdplus
  - user: name=sabnzbd home=/srv/nzb shell=/bin/false system=true
  - file: state=directory path=/srv/nzb/~queue~ owner=sabnzbd group=daemon mode=0777
  - file: state=directory path=/srv/nzb/.sabnzbd owner=sabnzbd group=daemon mode=0770
  - copy: src=files/sabnzbd/sabnzbdplus.default dest=/etc/default/sabnzbdplus
    notify: restart-sabnzbd
  - template: src=files/sabnzbd/sabnzbd.ini dest=/srv/nzb/.sabnzbd/sabnzbd.ini owner=sabnzbd group=daemon mode=0660
    notify: restart-sabnzbd
