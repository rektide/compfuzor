---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    pkgs:
    - gladish
    - laditools
    - ladish
    - projectm-jack
  vars_files:
  - vars/common.vars
  tasks:
  - apt: pkg=${pkgs} state=${APT_INSTALL}
    only_if: not ${APT_BYPASS}
  - file: src=files/jack/snd-aloop.conf dest=/etc/modules-load.d/snd.conf
  - file: src=files/jack/snd-aloop.conf dest=/etc/modules-load.d/snd-aloop.conf
  - file: src=files/jack/snd-aloop.conf dest=/etc/modprobe.d/snd-aloop-options.conf

