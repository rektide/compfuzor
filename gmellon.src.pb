---
- hosts: all
  vars:
    TYPE: gmellon
    INSTANCE: git
    # Not yet pushed; run with -e REPO_BYPASS=True until the origin exists,
    # then this clones/symlinks the standard src checkout.
    REPO: https://github.com/rektide/gmellon
    RUST: True
    # RUST_BIN defaults to TYPE (gmellon); install-rust.sh symlinks
    # target/release/gmellon into GLOBAL_BINS_DIR. No RUST_COPY: this is a
    # user CLI, not a sandboxed daemon, so the symlink-through-DIR install is
    # fine.

    # Zsh delivery: gmellon ships its own zimfw plugin inside the checkout
    # (zsh/init.zsh), wrapping the gmellon binary it builds -- plugin and
    # binary version together. This is a checkout-owned EXTERNAL module:
    # zmodule's source is an absolute path into {{DIR}}, which zimfw treats
    # as externally installed (never cloned/updated: see zimfw zmodule usage
    # "If an absolute path is given, the module is considered externally
    # installed and won't be installed or updated by zimfw"). The contributor
    # bridge (gen_zim) drops this fragment into zim/zimrc/active/ and
    # install-zimfw.sh imports it into the effective zim host context.
    # Ordering: the checkout must exist before zimfw rebuilds init.zsh
    # (zmodule eagerly errors on a missing module dir); same-playbook ordering
    # covers this, and a later checkout removal surfaces as ordinary zim
    # drift in status-zim.sh.
    ZIM_MODULES:
      - name: gmellon
        source: "{{DIR}}/zimfw"
        phase: tools
        comment: >
          SSH_AUTH_SOCK export (gcr socket, forwarding-safe) plus gkr-*
          helpers calling the gmellon binary -- gnome-keyring login-keyring
          unlock/re-key over the daemon control protocol, fully headless.
  tasks:
    - import_tasks: tasks/compfuzor.includes
