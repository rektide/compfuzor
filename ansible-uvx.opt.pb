---
- hosts: all
  vars:
    TYPE: ansible-uvx
    INSTANCE: main
    ENV:
      ansible_version: 12.0.0.a9
      ansible_core_version: 2.19rc2
    ENV_USER: True
    BINS:
      - name: install.sh
        content: |
          ux tool install ansible==${ANSIBLE_VERSION:-{{ENV.ansible_version}}} --prerelease=allow
          #commnity.general
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible-galaxy collection install community.postgresql
          # TODO it would be cool if compfuzor had reusable script to install global bin
          ln -s $(pwd)/bin/ansible{,-playbook} ${GLOBAL_BINS_DIR}/
      - name: path.sh
        basedir: False
        content: |
          echo PATH=\"$DIR/bin:\$PATH\"
          export PATH="$DIR/bin:$PATH"
      - name: ansible
        basedir: False
        global: True
        content: |
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible $*
      - name: ansible-playbook
        global: True
        basedir: False
        content: |
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible-playbook $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
