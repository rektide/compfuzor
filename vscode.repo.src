---
- hosts: all
  vars:
    TYPE: vscode
    INSTANCE: main
    APT_KEYRING_URL: https://packages.microsoft.com/keys/microsoft.asc 
    APT_KEYRING_DEARMOR: True
    APT_REPO: https://packages.microsoft.com/repos/vscode
    APT_COMPONENTS: main
    APT_DISTRIBUTION: stable
  tasks:
    - include: tasks/compfuzor.includes type=repo
