---
- hosts: all
  gather_facts: False
  vars:
    TYPE: ansible
    INSTANCE: git
    REPO: https://github.com/ansible/ansible.git
  vars_files:
  - vars/common.vars
  - vars/src.vars
  - vars/ansible.vars
  tasks:
  - include: tasks/cfvar_includes.tasks
  #- apt: state=${APT_INSTALL} pkg=python-jinja2,python-yaml,python-paramiko,python-apt,git
  #  when: not $APT_BYPASS
  #- template: src=files/ansible/{{ANSIBLE_ENV}} dest={{BINS_DIR}}/{{ANSIBLE_ENV}} mode=0755
  #- git: repo=https://github.com/pas256/ansible-ec2.git dest={{SRCS_DIR}}/ansible-ec2
  - file: src={{SRCS_DIR}}/ansible-ec2/bin/ansible-ec2 dest={{BINS_DIR}}/ansible-ec2 state=link
  #- file: dest=/etc/ansible state=directory
  - debug: msg="NAME {{SRCS_DIR}}/{{NAME}} {{DIR}}"
  - template: src=files/trivial dest=/tmp/wtf content="{{DIR}}"
  - file: src={{DIR}}/plugins/inventory/ec2.py dest=/etc/ansible/hosts.ec2 state=link
  - file: src={{DIR}}/plugins/inventory/ec2.ini dest=/etc/ansible/ec2.ini state=link
