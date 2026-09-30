---
- hosts: all
  vars_files:
    - vars/common.yaml
  vars:
    ETC_DIR: True
    TYPE: tailscale
    INSTANCE: main
    # apt repository lives in tailscale.repo.pb (same NAME/ETC) -- render
    # that first on a fresh box, or the PKGS lane cannot resolve tailscale.
    PKGS:
     - tailscale
  tasks:
    - import_tasks: tasks/compfuzor.includes
