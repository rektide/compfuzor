---
- hosts: all
  vars:
    TYPE: agentfs
    INSTANCE: git
    REPO: https://github.com/tursodatabase/agentfs
    RUST: True
    BINS:
      - name: build.sh
        generated: False
        content: |
          # todo: get good, use the dist-workspace thing?
          cd cli
          cargo +nightly build --release
          cd ..
          cd sandbox
          cargo +nightly build --release
          cd ..
          cd sdk
          cargo +nightly build --release
  tasks:
    - import_tasks: tasks/compfuzor.includes
