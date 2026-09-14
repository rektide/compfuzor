---
- hosts: all
  vars:
    TYPE: gmellon
    INSTANCE: git
    # Remotes configured (github rektide/gmellon + voodoo archive mirror) but
    # neither origin is published yet; run with -e REPO_BYPASS=True until one
    # exists, then this clones/symlinks the standard src checkout.
    REPO: https://github.com/rektide/gmellon
    RUST: True
    RUST_BIN: gmellon
    # install-rust.sh symlinks target/release/gmellon into GLOBAL_BINS_DIR.
    # RUST_BIN stays explicit: the workspace also builds harness binaries
    # (src/bin/real_daemon, src/bin/broker_collections) that must NOT be
    # installed -- only the single default RUST_BIN is. No RUST_COPY: user
    # CLI, not a ProtectHome daemon, so symlink-through-DIR is fine.

    # Zsh delivery: gmellon ships its own zimfw plugin inside the checkout
    # (zimfw/init.zsh + functions/), so plugin and binary version together.
    # This is a checkout-owned EXTERNAL module: zmodule's source is an
    # absolute path into {{DIR}}, which zimfw treats as externally installed
    # (never cloned/updated: see zimfw zmodule usage "If an absolute path is
    # given, the module is considered externally installed and won't be
    # installed or updated by zimfw"). The contributor bridge (gen_zim) drops
    # this fragment into zim/zimrc/active/ and install-zimfw.sh imports it
    # into the effective zim host context.
    # Ordering: the checkout must exist before zimfw rebuilds init.zsh
    # (zmodule eagerly errors on a missing module dir); same-playbook ordering
    # covers this, and a later checkout removal surfaces as ordinary zim
    # drift in status-zim.sh.
    ZIM_MODULES:
      - name: gmellon
        source: "{{DIR}}/zimfw"
        phase: tools
        comment: >
          Validated SSH_AUTH_SOCK selection (GMELLON_SSH_AUTH_SOCK override,
          never clobbers an existing live agent, discovers gcr/ssh then
          keyring/ssh; opt-in systemd-user publish) plus zsh completions
          regenerated from the gmellon binary when newer. Loading never
          prompts and works without the binary installed.
  tasks:
    - import_tasks: tasks/compfuzor.includes
