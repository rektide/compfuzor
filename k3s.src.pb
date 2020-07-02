---
- hosts: all
  vars:
    TYPE: k3c
    INSTANCE: git
    REPO: https://github.com/rancher/k3c
    OPT_DIRS: True
    BINS:
    - name: bin/build.sh
      run: True
      exec: |
        make build
        make image
   - global: k3c
     link: "{{OPT_DIR}}/bin/k3c"
  tasks:
  - includes: task/compfuzor.includes type=src
