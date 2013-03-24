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
  - apt: state=${APT_INSTALL} pkg=python-jinja2,python-yaml,python-paramiko,python-apt,git
    only_if: not $APT_BYPASS
  - template: src=files/ansible/$ANSIBLE_ENV dest=${BINS_DIR}/$ANSIBLE_ENV mode=0755
