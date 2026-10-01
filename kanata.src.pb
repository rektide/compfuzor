---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: git
    REPO: https://github.com/jtroo/kanata
    # Dev/exploration lane for kanata itself (the deployed service is
    # kanata.srv.pb, running the Debian package). RUST: True stages the
    # standard cargo build/install bins; the checkout doubles as local
    # documentation for the exact features of whatever release is out --
    # docs/ + cfg tests live in the tree.
    RUST: True
    RUST_BIN: kanata
    # libudev via the evdev/udev crates; pkg-config to find them
    PKGS:
      - build-essential
      - pkg-config
      - libudev-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
