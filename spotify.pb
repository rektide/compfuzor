---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: spotify
    APT_REPO: http://repository.spotify.com
    APT_DISTRIBUTION: stable
    APT_COMPONENT: non-free
    PKGS:
    - spotify-client
  tasks:
  - include: tasks/compfuzor.includes
  #- include: tasks/apt.key.install.tasks name=$NAME
  #- include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.srclist.install.tasks name=$NAME.unstable
  #- get_url: url="http://ftp.us.debian.org/debian/pool/main/o/openssl/libssl0.9.8_0.9.8o-4squeeze14_amd64.deb" dest="{{SRCS_DIR}}"
  #- shell: dpkg -i "{{SRCS_DIR}}/libssl0.9.8_0.9.8o-4squeeze14_amd64.deb"
  #- apt: state=${APT_INSTALL} pkg=spotify-client
