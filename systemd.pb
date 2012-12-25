---
- hosts: all
  user: root
  vars_files:
  - vars/apt.vars
  tasks:
  - apt: state=$APT_INSTALL pkg=systemd,python-dbus,libpam-systemd
  - shell: dpkg -s systemd|grep Status|grep installed;echo $?
    register: MISSING_SYSTEMD_SYSV
  - shell: echo 'Yes, do as I say!' | apt-get -o DPkg::options=--force-remove-essential -y --force-yes install systemd-sysv
    only_if: ${MISSING_SYSTEMD_SYSV.rc}
