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
    # explicit tcp_server (also in default features): Debian 1.9.0+ds-1
    # ships WITHOUT it -- no --port on /usr/bin/kanata, which blocks the
    # surface-dial TCP bridge direction (see
    # design/surface-dial-layers/routing0.gpt61s.md addendum).
    RUST_FEATURES: tcp_server
    # copy a real file to /usr/local/bin/kanata instead of a symlink:
    # the symlink would resolve through DIR (DIRMODE 0770) and repo/
    # (a git worktree of ~/archive/jtroo/kanata) -- untraversable for a
    # non-root daemon under ProtectHome like the _kanata services.
    RUST_COPY: True
    # libudev via the evdev/udev crates; pkg-config to find them
    PKGS:
      - build-essential
      - pkg-config
      - libudev-dev
  tasks:
    - import_tasks: tasks/compfuzor.includes
