---
- hosts: all
  vars:
    TYPE: cilium
    INSTANCE: main
    # https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt
    version: v0.18.6
    arch: "{{ 'arm64' if ansible_architecture == 'aarch64' else '' }}{{ 'amd64' if ansible_architecture == 'x86_64' else '' }}"
    TGZ: https://github.com/cilium/cilium-cli/releases/download/{{version}}/cilium-linux-{{arch}}.tar.gz
    TGZ_STRIP_COMPONENTS: 0
    GET_URLS:
      - "https://github.com/cilium/cilium-cli/releases/download/{{version}}/cilium-linux-{{arch}}.tar.gz.sha256sum"
    BINS:
      - link: "{{DIR}}/cilium"
        dest: "cilium"
        global: True
        delay: postRun
  tasks:
    - import_tasks: tasks/compfuzor.includes

