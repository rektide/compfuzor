---
# niri.etc.pb -- Niri keybinding consumer host deployment.
#
# One deployment, home-local material by default, user-first action audiences.
# Material lives at ${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/niri;
# the receiver remains ${XDG_CONFIG_HOME:-$HOME/.config}/niri. PREFIX_DIR can
# explicitly select shared material without changing the receiver audience.
# Retiring .user.pb was filename consolidation, not system-first placement.
#
# This deployment hosts the Niri KEYBINDING_CONSUMERS profile ONLY. It
# declares no KEYBINDING_ACTIONS/KEYBINDINGS of its own and installs no
# bindings itself: it advertises an owned consumer description. Producers
# (e.g. vicinae.src.pb) select that registry identity through install-keybindings.sh
# and accept bindings into the durable membership this profile owns.
#
# NO FABRICATED BASELINE: unlike Umbriel's installed system default
# (/usr/local/share/umbriel/config.toml), Niri has no packaged baseline
# config to layer. The profile below therefore declares no baseline. A
# MISSING ~/.config/niri/config.kdl is created by the consumer runtime as a
# minimal skeleton (just the managed insertion area -- nothing else is
# invented). The EXISTING live root is adopted conservatively by
# install.mjs / install-user.mjs:
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
    # Stable host identity; ETC must follow DIR instead of the /etc/opt hierarchy.
    NAME: niri
    PREFIX_DIR: "{{ ansible_env.XDG_DATA_HOME | default(ansible_env.HOME ~ '/.local/share', true) }}/compfuzor/etc"
    ETC: "{{DIR}}"
    ACTION_AUDIENCES: {default: user}
    # Root/membership/material paths are all invocation-time XDG defaults:
    # root config.kdl + .keybindings/ + keybindings/ under ~/.config/niri.
    # No baseline (see header); placement/registration default to link so
    # redeployed producer definitions track automatically.
    KEYBINDING_CONSUMERS:
      niri:
        profile_selector:
          env: COMPFUZOR_NIRI_PROFILE
          default: "{{ETC}}/keybinding-niri.json"
        contexts:
          user: {scope: user, root: config, subpath: niri}
    BINS:
      # User aggregate. The authored body performs conservative root
      # adoption/migration FIRST; the shared child runner then executes the
      # admitted complete keybinding host operation with native validation.
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

      Home-local etc-typed material under
      `${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/niri`, hosting the Niri
      keybinding consumer profile. The receiver root stays at
      `~/.config/niri/config.kdl` and is only modified by the user-scoped
      installer, which appends the managed insertion-area markers when
      absent and rebuilds only the entries between them.

      ## Install / adopt (as the desktop user)

      ```sh
      ansible-playbook -i 'localhost,' -c local niri.etc.pb
      material="${XDG_DATA_HOME:-$HOME/.local/share}/compfuzor/etc/niri"
      "$material/bin/install.mjs"
      "$material/bin/assemble.mjs" --check
      ```

      `install.mjs` and explicit `install-user.mjs` adopt the root (markers appended at EOF when
      missing; the old `vicinae` include block retired once; `handy` and any
      other text untouched) and then runs the generated
      complete keybinding host operation, which rebuilds the
      managed area from the durable membership and validates the full
      include closure with the installed `niri` binary.

      Producers register into this consumer with their own generated
      installers, e.g. `/usr/local/src/vicinae-git/bin/install-user.sh`.

      `assemble.mjs` / `assemble-user.mjs` reassemble existing placements;
      `--check` validates without publishing. No system receiver is declared,
      so no install-system.mjs or assemble-system.mjs is emitted.
      Shared material is explicit: render with `-e PREFIX_DIR=/etc/opt` and advertise
      that host's owned description. Same-ID foreign owner references are not silently
      retargeted; choose a distinct identity/policy or reconcile deliberately.
      Existing deployments are not moved, pruned or activated automatically.

      ## Files

      - `etc/keybinding-niri.json` -- generated consumer profile
      - `bin/install-user.mjs` + `bin/install.mjs` -- user-default action family
      - `bin/assemble-user.mjs` + `bin/assemble.mjs` -- existing-placement assembly
      - `bin/install-user.sh` -- internal original-path adoption body
      - `bin/install-keybindings-niri.sh` / `bin/keybindings.mjs` -- compatible internal endpoints
      - `keybindings/consumers/user/niri.json` -- owned registry description referencing this profile
      - `bin/register-keybindings-consumer-niri-user.sh` / `bin/status-keybindings-consumer-niri-user.sh` -- passive reference publication/status, no native activation

      Requires node, jq, `block-in-file`, and `niri` on PATH at invocation
      time; none are installed by this deployment.
  tasks:
    - import_tasks: tasks/compfuzor.includes
