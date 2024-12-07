---
- hosts: all
  vars_files:
    - vars/common.yaml
  vars:
    TYPE: tailscale
    INSTANCE: main
    APT_LIST_URL: "https://pkgs.tailscale.com/stable/debian/{{APT_DEFAULT_DISTRIBUTION}}.tailscale-keyring.list"
    APT_KEYRING_URL: "https://pkgs.tailscale.com/stable/debian/{{APT_DEFAULT_DISTRIBUTION}}.noarmor.gpg"
    APT_TRUSTED: tailscale-archive-keyring # hardcoded in downloaded .list
    APT_ARCH: true
    PKGS:
     - tailscale
  tasks:
  #- include: tasks/compfuzor/apt.tasks
  - include: tasks/compfuzor/pkgs.tasks
