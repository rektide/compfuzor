---
- hosts: all
  gather_facts: False
  vars:
    NAME: logmein
    APT_REPO: http://ppa.launchpad.net/webupd8team/haguichi/ubuntu
    APT_DISTRIBUTION: "{{UBUNTU_DISTRIBUTION}}"
    APT_TRUST: False
    PKGS_BYPASS: True
    PKGS:
    - haguichi
    logme_deb: logmein-hamachi_2.1.0.119-1_amd64.deb
    logme_url: "https://secure.logmein.com/labs/{{logme_deb}}"
  tasks:
  - include: tasks/compfuzor.includes type="pkg"
  - get_url: url="{{logme_url}}" dest="{{SRCS_DIR}}/"
  - shell: chdir="{{SRCS_DIR}}" dpkg -i "{{logme_deb}}"
  - apt: pkg={{item}} state="{{APT_INSTALL}}"
    with_items: PKGS
