---
- hosts: all
  user: root
  vars_files:
  - vars/common.vars
  tasks:
  - apt: state=$APT_INSTALL pkg=systemd,python-dbus,libpam-systemd
  - shell: dpkg -s systemd-sysv 2>&1|grep Status|grep installed;echo $?
    register: MISSING_SYSTEMD_SYSV
  - shell: echo 'Yes, do as I say!' | apt-get -o DPkg::options=--force-remove-essential -y --force-yes install systemd-sysv
    only_if: ${MISSING_SYSTEMD_SYSV.stdout} != "1"
