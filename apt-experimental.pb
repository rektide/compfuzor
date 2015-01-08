---
- hosts: all
  gather_facts: False
  vars:
    APT_PIN: "release n=experimental"
    APT_PIN_PRIORITY: 200
  tasks:
  - file: path=/etc/apt/preferences.d state=directory
  # zz makes this last call.
  - template: src=files/_apt-pin dest=/etc/apt/preferences.d/zz-experimental-codename
