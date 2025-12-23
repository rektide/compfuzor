---
- hosts: all
  vars:
    REPO: https://github.com/containers/composefs-rs
    RUST: True
    PKGS:
      - erofs-utils
      - erofsfuse
    BINS:
      # oh no, both BINS and LINKS can do links
      - link: ../target/release/cfsctl
        global: True
        delay: "{{_postRun}}"
      - link: ../target/release/erofs-debug
        global: True
        delay: "{{_postRun}}"
      - link: ../target/release/composefs-setup-root
        global: True
        delay: "{{_postRun}}"
  tasks:
    - import_tasks: tasks/compfuzor.includes
