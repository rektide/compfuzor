---
- hosts: all
  vars:
    REPO: https://github.com/ollama/ollama
    PKGS:
      - glslc
    CMAKE: True
    BINS:
      - name: build.sh
        generatedAt: early
        content: |
          go build
      - name: dev.sh
        basedir: False
        content: |
          go run "{{DIR}}" ${*:-serve}
      - name: install.sh
        content: |
          ln -sfv {{DIR}}/ollama $GLOBAL_BINS_DIR/ollama
  tasks:
    - import_tasks: tasks/compfuzor.includes
