---
- hosts: all
  sudo: True
  gather_facts: False
  vars:
    pkgs:
    - jackd2
    - zita-ajbridge
    - ladish
  tasks:
  - apt: pkg=${pkgs} state=${APT_INSTALL}
  - file: src=files/jack/snd.conf dest=/etc/modules-load.d/snd.conf
  - file: src=files/jack/snd-aloop.conf dest=/etc/modules-load.d/snd-aloop.conf
  - file: src=files/jack/snd-aloop-options.conf dest=/etc/modprobe.d/snd-aloop-options.conf
