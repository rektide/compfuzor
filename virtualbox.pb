---
- hosts: all
  sudo: True
  tags:
  - packages
  - root
  gather_facts: False
  vars:
    NAME: virtualbox
    APT_REPO: http://download.virtualbox.org/virtualbox/debian
    APT_DISTRIBUTION: wheezy
    APT_COMPONENT: contrib
    # via: https://www.virtualbox.org/wiki/Downloads
    extra: http://download.virtualbox.org/virtualbox/4.2.16/Oracle_VM_VirtualBox_Extension_Pack-4.2.16-86992.vbox-extpack
  vars_files:
  - vars/common.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  - include: tasks/apt.key.install.tasks name=$NAME
  - include: tasks/apt.list.install.tasks name=$NAME.unstable
  #- include: tasks/apt.srclist.install.tasks name=$NAME.unstable
  - apt: state=${APT_INSTALL} pkg=dkms,virtualbox-4.2
    only_if: not ${APT_BYPASS}
  - file: path=/usr/local/share/virtualbox state=directory
  - get_url: url={{extra}} dest=/usr/local/share/virtualbox
