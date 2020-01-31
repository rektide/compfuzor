---
- hosts: all
  vars:
    NAME: neovide
    TYPE: git
    REPO: https://github.com/Kethku/neovide
    PKGS:
    - mesa-vulkan-drivers
    - vulkan-tools
  tasks:
  - include: tasks/compfuzor.includes type=src
