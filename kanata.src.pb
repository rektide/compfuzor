---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: git
    REPO: https://github.com/jtroo/kanata
    # Production binary build lane for kanata: builds and copy-installs
    # the source binary (/usr/local/bin/kanata, tcp_server enabled --
    # RUST_COPY so sandboxed _kanata services can execute it) that the
    # main/BlueTurn/kinata instances run. Configuration and units are
    # owned by the service playbooks (kanata.srv.pb,
    # kanata-blueturn.srv.pb, kinata.srv.pb), NOT here. As of 2026-10-06
    # the Debian package still backs the live services; the source
    # binary is staged pending the Services G cutover declarations. The
    # checkout (a worktree of ~/archive/jtroo/kanata) doubles as local
    # documentation for the built release -- docs/ + cfg tests live in
    # the tree.
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
