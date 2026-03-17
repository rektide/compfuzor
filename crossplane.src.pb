---
- hosts: all
  vars:
    REPO: https://github.com/crossplane/crossplane
    GO: True
    GO_TARGET: ./cmd/crossplane/main.go
    BINS:
      - name: build.sh
        content: |
          go build -o crank ./cmd/crank/main.go
      - name: install.sh
        content: |
          ln -sfv "$(pwd)/crank" $GLOBAL_BINS_DIR/
  tasks:
    - import_tasks: tasks/compfuzor.includes
