---
- hosts: all
  vars:
    REPO: https://github.com/quickwit-oss/quickwit
    TOOL_VERSIONS:
      rust: 1
      yarn: 4
    PKGS:
      - protobuf-compiler
    ENV: True
    BINS:
      - name: build.sh
        content: |
          # theres some lockfile stuff that gets in the way without this yarn install,
          # please try to remove latter?
          (
            cd quickwit/quickwit-ui;
            yarn install
          )
          make build-ui
          (
            cd quickwit;
            cargo build --release --features release-feature-set
          )
      - name: install.sh
        content: |
          ln -sfv $(pwd)/quickwit/target/release/quickwit
  tasks:
    - import_tasks: tasks/compfuzor.includes
