---
- hosts: all
  vars:
    TYPE: citron
    INSTANCE: git
    REPO: https://git.citron-emu.org/citron/emu.git
    ENVS:
      hi: ho
    DIRS:
     - build
    BINS:
      - name: build.sh
        basedir: build
        run: True
        exec: |
          cmake -DCMAKE_INSTALL_PREFIX={{OPT}} {{REPO_DIR}}
          make
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
