---
- hosts: all
  vars:
    TYPE: anyrun
    INSTANCE: git
    REPO: https://github.com/anyrun-org/anyrun
    ENV:
      womp: womp
    BINS:
      - name: build.sh
        exec: |
          cargo build --release
      - name: install.sh
        exec: |
          cargo install --path anyrun/
          mkdir -p ~/.config/anyrun/plugins
          cp target/release/*.so ~/.config/anyrun/plugins
          cp examples/config.ron ~/.config/anyrun/config.ron
  tasks:
    - import_tasks: tasks/compfuzor.includes
