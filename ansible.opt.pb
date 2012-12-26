---
- hosts: all
  user: root
  vars_files:
  - vars/common.vars
  - vars/ansible.vars
  tasks:
  - git: repo=https://github.com/ansible/ansible.git dest=${OPT_DIR}/ansible-git
  - file: path=$BIN_DIR state=directory
  - template: src=files/ansible/$ANSIBLE_ENV dest=${BIN_DIR}/$ANSIBLE_ENV mode=0755
  - include: tasks/ansible.deps.tasks
