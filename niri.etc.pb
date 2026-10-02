---
# niri.etc.pb -- Niri keybinding consumer host deployment.
#
# Location-typed deployment (TYPE=etc => material under /etc/opt/niri) that
# carries USER-SCOPED installers: the operator runs bin/install-user.sh as
# themselves, and the bound consumer context resolves ~/.config/niri at
# invocation time. "user" is an audience of this deployment's installers,
# not a place for deployment material -- there is deliberately no niri.user.pb
# (same one-deployment-per-compositor decision as umbriel.etc.pb).
#
# This deployment hosts the Niri KEYBINDING_CONSUMERS profile ONLY. It
# declares no KEYBINDING_ACTIONS/KEYBINDINGS of its own and installs no
# bindings itself: producers (e.g. vicinae.src.pb) bind this deployment as
# their niri consumer target, and their generated install-keybindings-niri.sh
# registers bindings into the durable membership this profile owns.
#
# NO FABRICATED BASELINE: unlike Umbriel's installed system default
# (/usr/local/share/umbriel/config.toml), Niri has no packaged baseline
# config to layer. The profile below therefore declares no baseline. A
# MISSING ~/.config/niri/config.kdl is created by the consumer runtime as a
# minimal skeleton (just the managed insertion area -- nothing else is
# invented). The EXISTING live root is adopted conservatively by
# install-user.sh:
#   * the insertion-area marker pair is appended at EOF when absent
#     (trailing top-level comments are valid KDL); existing text --
#     output blocks, the handy block, config.d includes, personal binds,
#     anything unknown -- is never rewritten;
#   * the old `vicinae` block-in-file namespace (include lines maintained
#     by vicinae.src.pb's removed install-niri.sh) is retired exactly once
#     as a migration: producers now supply those bindings inside the
#     managed insertion area. The ~/.config/niri/vicinae/ symlinks it
#     created are deliberately NOT pruned.
#
# Prerequisites (not installed here): node for the bundled keybindings
# runtime, jq, block-in-file, and the niri binary for native validation.
# See doc/config/keybinding-producers.md and keybinding-consumers.md.
- hosts: all
  vars:
    TYPE: niri
    # Pin NAME: the implicit instance suffix would put deployment material
    # at /etc/opt/niri-main, and producers bind /etc/opt/niri.
    NAME: niri
    # Root/membership/material paths are all invocation-time XDG defaults:
    # root config.kdl + .keybindings/ + keybindings/ under ~/.config/niri.
    # No baseline (see header); placement/registration default to link so
    # redeployed producer definitions track automatically.
    KEYBINDING_CONSUMERS:
      niri:
        contexts:
          user: {scope: user, root: config, subpath: niri}
    BINS:
      # User aggregate. The authored body performs conservative root
      # adoption/migration FIRST; gen_bins then appends the generated
      # install-keybindings-niri.sh child (host assembly: membership-driven
      # rebuild of the managed area + native validation) after it.
      - name: install-user.sh
        deployment_rooted: True
        content: |
          # Conservative adoption of the live Niri root. Never rewrites
          # existing text; only appends the managed insertion area and
          # retires the superseded vicinae include block.
          NIRI_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/niri"
          NIRI_CONFIG="$NIRI_DIR/config.kdl"
          mkdir -p "$NIRI_DIR"
          if [ ! -e "$NIRI_CONFIG" ]; then
            # Missing root: start from the minimal managed-area skeleton
            # (the consumer runtime's seed mode would create the same
            # shape; doing it here keeps adoption explicit and idempotent).
            printf '// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n' > "$NIRI_CONFIG"
          elif ! grep -qx '// compfuzor-keybindings-begin' "$NIRI_CONFIG"; then
            # Existing root without the adopted area: append the marker pair
            # at EOF. Trailing top-level comments are valid KDL; every
            # existing line stays untouched.
            printf '\n// compfuzor-keybindings-begin\n// compfuzor-keybindings-end\n' >> "$NIRI_CONFIG"
          fi
          # One-time migration: retire the old `vicinae` block-in-file
          # namespace (vicinae.src.pb's removed install-niri.sh). Producers
          # now supply those bindings inside the managed area. Idempotent:
          # removing an absent block is a no-op.
          block-in-file --remove vicinae --comment "//" "$NIRI_CONFIG"
    README: |
      # niri.etc.pb

      Etc-typed deployment (material under `/etc/opt/niri`) hosting the Niri
      keybinding consumer profile. The live root stays at
      `~/.config/niri/config.kdl` and is only modified by the user-scoped
      installer, which appends the managed insertion-area markers when
      absent and rebuilds only the entries between them.

      ## Install / adopt (as the desktop user)

      ```sh
      ansible-playbook -i 'localhost,' -c local niri.etc.pb
      /etc/opt/niri/bin/install-user.sh
      ```

      `install-user.sh` adopts the live root (markers appended at EOF when
      missing; the old `vicinae` include block retired once; `handy` and any
      other text untouched) and then runs the generated
      `install-keybindings-niri.sh` host assembly, which rebuilds the
      managed area from the durable membership and validates the full
      include closure with the installed `niri` binary.

      Producers register into this consumer with their own generated
      installers, e.g. `/usr/local/src/vicinae-git/bin/install-user.sh`.

      ## Files

      - `etc/keybinding-niri.json` -- generated consumer profile
      - `bin/install-user.sh` -- adoption + host assembly aggregate
      - `bin/install-keybindings-niri.sh` -- generated host installer
      - `bin/keybindings.mjs` -- generated shared keybindings runtime

      Requires node, jq, `block-in-file`, and `niri` on PATH at invocation
      time; none are installed by this deployment.
  tasks:
    - import_tasks: tasks/compfuzor.includes
