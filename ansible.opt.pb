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
  - template: src=files/ansible/{{ANSIBLE_ENV}} dest={{BINS_DIR}}/{{ANSIBLE_ENV}} mode=0755
  - git: url=https://github.com/pas256/ansible-ec2.git path={{SRCS_DIR}}/ansible-ec2
  - file: src={{SRCS_DIR}}/bin/ansible-ec2 dest={{BINS_DIR}}/ansible-ec2 state=link
