---
- hosts: all
  vars:
    TYPE: ansible-uvx
    INSTANCE: main
    ENV:
      ansible_version: 12.0.0.a9
      ansible_core_version: 2.19rc2
    BINS:
      - name: install.sh
        content: |
          ux tool install ansible==${ANSIBLE_VERSION:-12.0.0a9} --prerelease=allow
          #uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-2.19rc2} ansible-galaxy collection install commnity.general community.postgresql
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-2.19rc2} ansible-galaxy collection install community.postgresql
      - name: ansible
        basedir: False
        content: |
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-2.19rc2} ansible $*
      - name: ansible-playbook
        basedir: False
        content: |
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-2.19rc2} ansible-playbook $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
