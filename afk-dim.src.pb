---
# afk-dim.src.pb — dim displays when the Wayland session goes idle.
#
# First-party rektide project, jj-native. Remotes (github rektide/afk-dim +
# voodoo archive mirror) are configured but neither origin is published yet:
# run with -e REPO_BYPASS=True until one exists, then this clones/symlinks
# the standard src checkout (gmellon.src.pb precedent).
#
# GIT_DIR points the deployment workspace at the live dev checkout at
# ~/src/afk-dim: fs_repo symlinks DIR/repo there, so build-rust.sh builds the
# dev tree in place (shared target/). install-rust.sh RUST_COPY=true copies
# (not symlinks) target/release/afk-dim into GLOBAL_BINS_DIR — a deployed
# session daemon should not break because the dev tree moved.
#
# Runtime deps beyond build headers: ddccontrol (the ddccontrol provider
# shells out to it at runtime). PKGS are declarative; both were already
# installed when this switched from hand-install.
- hosts: all
  vars:
    TYPE: afk-dim
    INSTANCE: git
    REPO: https://github.com/rektide/afk-dim
    GIT_DIR: /home/rektide/src/afk-dim
    RUST: True
    RUST_COPY: true
    PKGS:
      - libwayland-dev
      - ddccontrol
  tasks:
    - import_tasks: tasks/compfuzor.includes
