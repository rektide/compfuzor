---
- hosts: all
  tags:
  - packages
  - root
  vars:
    TYPE: nodesource
    INSTANCE: 26.x
    NAME: "{{TYPE}}-{{INSTANCE}}"
    APT_REPO: "https://deb.nodesource.com/node_{{INSTANCE}}"
    # nodesource publishes one `nodistro` suite for every debian/ubuntu
    # release (no codename dists anymore), so forky/sid is covered.
    APT_DISTRIBUTION: nodistro
    APT_KEYRING_URL: "https://deb.nodesource.com/gpgkey/nodesource.gpg.key"
    APT_DEARMOR: True
    PKGS:
    - nodejs
  tasks:
  - import_tasks: tasks/compfuzor.includes
