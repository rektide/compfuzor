- hosts: all
  vars:
    TYPE: unetbootin
    INSTANCE: repo
    APT_REPO: http://ppa.launchpad.net/gezakovacs/ppa/ubuntu
    PKGS:
    - unetbootin
  tasks:
  - include: tasks/compfuzor.includes type=opt
