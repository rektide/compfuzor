---
- hosts: all
  vars:
    NAME: neovide
    TYPE: git
    REPO: https://github.com/Kethku/neovide
    PKGS:
    - mesa-vulkan-drivers
    - vulkan-tools
    BINS:
    - name: build.sh
      exec: cargo build --release
      run: True
    - link: ./target/release/neovide
      phase: postRun
      global: True
  tasks:
  - include: tasks/compfuzor.includes type=src
