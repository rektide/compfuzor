---
- hosts: all
  vars:
    TYPE: lact
    INSTANCE: git
    REPO: https://github.com/ilya-zlobintsev/LACT
    ENV: true
    PKGS:
      - ocl-icd-opencl-dev
    BINS:
      - name: build.sh
        content: |
          cargo build --release
      - name: install.sh
        content: |
          ln -s target/release/lact ${GLOBAL_BINS_DIR}/
  tasks:
    - import_tasks: tasks/compfuzor.includes
