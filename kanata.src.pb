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
    # kanata-blueturn.srv.pb, kinata.srv.pb), NOT here. The Debian
    # package was removed 2026-10-07 (remove, not purge); main and
    # BlueTurn run this binary -- cutover0.glm53.md. The checkout (a
    # worktree of ~/archive/jtroo/kanata) doubles as local documentation
    # for the built release -- docs/ + cfg tests live in the tree.
    #
    # PATCHED AHEAD OF UPSTREAM (2026-10-13): the deployed binary
    # carries files/kanata/event-order-total-order.patch -- upstream's
    # event-reorder sort (introduced by #1931) used a comparator that
    # is not a total order, and Rust's sort panicked on a real typing
    # burst, killing the service (see kanata.srv.pb's Restart note).
    # The patch reorders within same-press-status runs only; all 9
    # upstream collect_and_sort_events tests pass. ansible's git lane
    # resets this checkout to origin/HEAD on update, silently dropping
    # local commits -- reapply the patch and rebuild after any
    # kanata.src.pb run until upstream merges a fix (then reference
    # it via PR_PATCHES instead).
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
