---
- hosts: all
  vars:
    TYPE: k3c
    INSTANCE: git
    REPO: https://github.com/rancher/k3c
    BINS:
    - name: build.sh
      run: True
      exec: |
        make build
        #make package
    - dest: k3c
      global: True
  tasks:
  - include: tasks/compfuzor.includes type=src
