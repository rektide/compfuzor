---
- hosts: all
  vars:
    TYPE: ansible-uvx
    INSTANCE: main
    ENV:
      ansible_version: 12.0.0
      ansible_core_version: 2.19.2
      ansible_collections: "community.postgresql ansible.utils"
      ansible_withs: "--with {{DEPS|join(' --with ')}}"
    DEPS:
      - netaddr
    ENV_USER: True
    BINS:
      - name: install.sh
        content: |
          uv tool install ansible==${ANSIBLE_VERSION:-{{ENV.ansible_version}}} --prerelease=allow
          #commnity.general
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible-galaxy collection install $ANSIBLE_COLLECTIONS
          # TODO it would be cool if compfuzor had reusable script to install global bin
          ln -s $(pwd)/bin/ansible{,-playbook,-galaxy} ${GLOBAL_BINS_DIR}/
      - name: path.sh
        basedir: False
        content: |
          echo PATH=\"$DIR/bin:\$PATH\"
          export PATH="$DIR/bin:$PATH"
      - name: ansible
        basedir: False
        global: True
        content: |
          uvx $ANSIBLE_WITHS --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible $*
      - name: ansible-playbook
        global: True
        basedir: False
        content: |
          uvx $ANSIBLE_WITHS --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible-playbook $*
      - name: ansible-galaxy
        global: True
        basedir: False
        content: |
          uvx --from ansible-core==${ANSIBLE_CORE_VERSION:-{{ENV.ansible_core_version}}} ansible-galaxy $*

  tasks:
    - import_tasks: tasks/compfuzor.includes
