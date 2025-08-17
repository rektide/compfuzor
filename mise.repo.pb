---
- hosts: all
  vars:
    TYPE: mise
    INSTANCE: main
    APT_REPO: https://mise.jdx.dev/deb 
    APT_DISTRIBUTION: stable
    APT_KEYRING_URL: https://mise.jdx.dev/gpg-key.pub 
    APT_DEARMOR: True
    PKGS:
      - mise
  tasks:
    - import_tasks: tasks/compfuzor.includes


