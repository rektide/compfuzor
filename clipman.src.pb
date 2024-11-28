---
- hosts: all
  vars:
    TYPE: clipman
    INSTANCE: src
    REPO: https://github.com/chmouel/clipman
    ENV:
      GLOBAL_BINS_DIR: "{{GLOBAL_BINS_DIR}}"
      GOPATH: "{{BUILD_DIR}}"
    DIRS:
      - build
    BINS:
      - name: build.sh
        exec: |
          mkdir -p $GOPATH
          go install
          [ -e bin/clipman ] || [ -h bin/clipman ] || ln -s $GOPATH/bin/clipman bin/
      - name: install.sh
        exec: |
          cp $GOPATH/bin/clipman {{GLOBAL_BINS_DIR}}/
  tasks:
    - import_tasks: tasks/compfuzor.includes
