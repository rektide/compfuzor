---
- hosts: all
  vars:
    TYPE: k3c
    INSTANCE: git
    REPO: https://github.com/rancher/k3c
    OPTS_DIRS: True
    BINS:
    - name: build.sh
      run: True
      exec: |
        make build
        make image
    - link: k3c
      global: true
  tasks:
  - include: tasks/compfuzor.includes type=src
