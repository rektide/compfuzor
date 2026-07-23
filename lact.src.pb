---
- hosts: all
  vars:
    REPO: https://github.com/ilya-zlobintsev/LACT
    RUST: True
    # RUST_PKG: lact
    RUST_COMMENT: "build only the `lact` binary instead of the whole workspace (skips lact-gui/GTK); set RUST_PKG: lact to enable"
    PKGS:
      - ocl-icd-opencl-dev
    SYSTEMD_SERVICES:
      ExecStart: lact daemon
      Nice: -10
  tasks:
    - import_tasks: tasks/compfuzor.includes
