---
- hosts: all
  vars:
    REPO: https://github.com/dolthub/dolt
    GO: True
    GO_TARGET:  ./cmd/dolt
    BINS:
      # TODO: make a general parameter for bin/install basedir
      - name: build.sh
        basedir: repo/go
      - name: install.sh
        basedir: repo/go
  tasks:
    - import_tasks: tasks/compfuzor.includes
