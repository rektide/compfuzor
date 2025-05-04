---
- hosts: all
  vars:
    TYPE: asdf
    INSTANCE: git
    REPO: https://github.com/asdf-vm/asdf.git
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          make
      - name: install.sh
        exec: |
          ln -sf $(pwd)/asdf $GLOBAL_BINS_DIR
      - name: install-user.sh
    ETC_FILES:
      - name: plugins.json
        content: "{{plugins|to_nice_json}}"
    VAR_DIRS:
      - data
    plugins:
      - name: java
        version: openjdk-20
      - name: clojure
        url: https://github.com/halcyon/asdf-clojure.git
      - name: deno
      - name: nodejs
      - name: protonge
      - name: rust
      - name: pnpm
        url: https://github.com/jonathanmorley/asdf-pnpm
      - name: zig
        url: https://github.com/asdf-community/asdf-zig.git
      - name: yarn
        url: https://github.com/twuni/asdf-yarn
  tasks:
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: src
