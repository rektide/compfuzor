---
# umbriel.etc.pb -- Umbriel user-config deployment + keybinding consumer host.
#
# Absorbs every role of the former umbriel.user.pb:
#   * owns the ROOT user config, ~/.config/umbriel/config.toml -- a thin
#     [include] chain over the system default (/usr/local/share/umbriel/
#     config.toml, installed by umbriel.src.pb), with the keybinding
#     insertion area inside the single include.files array, and
#   * stages the personal fragments keybinds-local.toml (chord overrides)
#     and animation.toml (focus-navigation motion tuning) as deployment
#     material, and
#   * hosts the Umbriel KEYBINDING_CONSUMERS profile: producers (e.g.
#     vicinae.src.pb) bind this deployment as their umbriel target, and the
#     consumer-owned vicinae-clipboard chord patch below lives here.
#
# WHY .etc, NOT .user (operator decision): ONE deployment per compositor,
# location-typed. "user" is an audience of this deployment's USER-SCOPED
# installers, not a place to store deployment material. Deployment material
# renders under /etc/opt/umbriel (TYPE=etc => DIR=ETC=ETCS_DIR/NAME); the
# live user config under ~/.config/umbriel is only ever touched by the
# operator running bin/install-user.sh as themselves, which resolves
# HOME/XDG at invocation time. There is deliberately no .user.pb anymore,
# and a future "thing that runs" umbriel service-instance deployment
# (.srv.pb) is intentionally not built here.
#
# Why the root config is a chain, and why it must NOT carry a [keybinds]
# table of its own -- Umbriel's config model, learned the hard way:
#   * Umbriel loads the FIRST config found (user, XDG_CONFIG_DIRS, data dir)
#     and never auto-layers. A user config that wanted keybinds would
#     otherwise have to carry a full copy of the built-in default set,
#     because:
#   * A config file's [keybinds] table REPLACES the entire built-in set.
#     The per-load seeding (src/config/config.cpp:2553/2584,
#     loaded.keybinds = defaultKeybinds()) is dead code: parseInto builds a
#     fresh Config (config.cpp:2476) and move-assigns it over the caller's
#     (config.cpp:2509). Only binds redefining the same chord are dropped.
#   * The chord-by-chord [keybinds] merging that DOES exist
#     (src/config/config.cpp readKeybinds, fed by mergeWithIncludes at
#     config.cpp:2455) merges across [include] files, never against
#     built-in defaults. That merge is exactly what this chain relies on.
#   * [include] may appear at most once per TOML file, so this root file is
#     the single place the chain is declared; the keybinding insertion area
#     lives inside its files array, and fragments attach as optional
#     includes rather than by editing live user text.
#
# Division of labor across compfuzor entries:
#   umbriel.src.pb  -- source build; installs /usr/local/share/umbriel/
#                      config.toml (the chain's baseline) and the binaries
#   umbriel.etc.pb  -- this entry: root template + personal fragments +
#                      the Umbriel keybinding consumer host/profile
#   vicinae.src.pb  -- named keybinding producer; its generated
#                      install-keybindings-umbriel.sh registers bindings
#                      into this consumer (the old hand-written
#                      keybinds-vicinae.toml fragment + install-umbriel.sh
#                      are gone; the hardcoded include was dropped from the
#                      root template deliberately, not by pruning)
#
# ONE-TIME ADOPTION / MIGRATION (run bin/install-user.sh once as yourself):
#   * missing files are seeded from the deployment material;
#   * a live file that still BYTE-MATCHES the previously managed
#     umbriel.user.pb template is migrated to the new template (the
#     byte-match proves there is no user-authored text to lose);
#   * a live file that matches neither (user edits) is NEVER overwritten:
#     a note is printed and the operator adapts it by hand if desired.
# The previously managed template hashes are pinned in UMBRIEL_MIGRATIONS
# below; they are the exact bytes umbriel.user.pb rendered (see jj history
# of files/umbriel/* at the commit before this playbook existed).
#
# Prerequisites (not installed here): node for the bundled keybindings
# runtime, jq, block-in-file, and the umbriel binary for native validation.
# See doc/config/keybinding-producers.md for the package/external-command
# conventions.
- hosts: all
  vars:
    TYPE: umbriel
    # Pin NAME: the implicit instance suffix would put deployment material
    # at /etc/opt/umbriel-main, and producers bind /etc/opt/umbriel.
    NAME: umbriel
    ETC_FILES:
      # Root include-chain template (staged at {{ETC}}/config.toml). Also
      # bound as the consumer profile's template_file, so a MISSING live
      # root is seeded from this exact shape by the runtime as well.
      - config.toml
      # Personal chord overrides; loaded by the root chain's optional.files
      # AFTER the keybinding insertion area, so these win same-chord
      # conflicts. Mod+Grave is owned by the consumer patch below.
      - keybinds-local.toml
      # Animation tuning (focus-navigation reveal rides windows_move);
      # loaded by optional.files; merges key-by-key over the default.
      - animation.toml
    # Live seeds byte-match the previously managed umbriel.user.pb template
    # content exactly once: only then may the installer replace them. Map of
    # staged file name -> sha256 of the OLD managed bytes (the new bytes are
    # compared against the staged deployment material itself).
    UMBRIEL_MIGRATIONS:
      config.toml: 485fe1da5e7c87527226a52d1a0c8c2d1fb62d9b51928d210a545d94c3be4db1
      keybinds-local.toml: dde2cc41725cd7638ae78f5bc2c4ec498f074900151df056cd85d48cf6e9341c
      animation.toml: 0e2bb0455a12595004387ef7fcc0df35b2a25e3a2f867cc21f79844f697b61af
    # Consumer host profile. Registration/placement default to link: managed
    # YAML registration links and native receiver links track the producer's
    # redeployed definitions, while edited COPIES (if a user switches a
    # binding to copy placement) always win. template_file pins the
    # missing-root skeleton to the staged template above (it already carries
    # baseline + insertion area + optional personal entries, so no separate
    # baseline/personal bootstrap policy is declared here).
    KEYBINDING_CONSUMERS:
      umbriel:
        contexts:
          user: {scope: user, root: config, subpath: umbriel}
        template_file: "{{ETC}}/config.toml"
        registration: link
        placement: link
    # Consumer-owned late patch layer: the Umbriel chord policy for the
    # producer-owned vicinae clipboard binding. patch: true keeps it dormant
    # (whenPresent) while the vicinae producer is absent or disabled; it
    # never re-declares the command. This replaces keybinds-local.toml's old
    # duplicate command-valued Mod+Grave entry.
    KEYBINDINGS:
      vicinae-clipboard:
        patch: true
        umbriel:
          keys: [Mod+Grave]
    BINS:
      # User aggregate. The authored body seeds/migrates the live config
      # FIRST; gen_bins then appends the generated install-keybindings-
      # umbriel.sh child (host assembly: membership-driven root rebuild +
      # native validation) after it.
      - name: install-user.sh
        deployment_rooted: True
        content: |
          # Conservative seed/migrate of the live Umbriel user config. User
          # text always wins: only verbatim previously-managed bytes are
          # ever replaced, and only with the current staged template.
          UMBRIEL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/umbriel"
          mkdir -p "$UMBRIEL_DIR"

          umbriel_seed() { # <live-path> <staged-name> <old-managed-sha256>
            _live="$1" _name="$2" _old="$3"
            _staged="$DIR/$_name"
            [ -f "$_staged" ] || { echo "umbriel: missing staged material: $_staged" >&2; return 1; }
            if [ ! -e "$_live" ]; then
              cp "$_staged" "$_live"
              echo "umbriel: seeded $_live"
              return 0
            fi
            if cmp -s "$_live" "$_staged"; then
              return 0
            fi
            if [ "$(sha256sum "$_live" | awk '{print $1}')" = "$_old" ]; then
              cp "$_staged" "$_live"
              echo "umbriel: migrated $_live from the previously managed template"
              return 0
            fi
            echo "umbriel: NOTE: $_live has user edits (matches neither the current" >&2
            echo "umbriel: nor the previously managed template); left untouched." >&2
            echo "umbriel: Adopt the current template by hand if desired; the keybinding" >&2
            echo "umbriel: insertion area must sit inside its single [include] files array." >&2
          }

          umbriel_seed "$UMBRIEL_DIR/config.toml" config.toml {{UMBRIEL_MIGRATIONS['config.toml']}}
          umbriel_seed "$UMBRIEL_DIR/keybinds-local.toml" keybinds-local.toml {{UMBRIEL_MIGRATIONS['keybinds-local.toml']}}
          umbriel_seed "$UMBRIEL_DIR/animation.toml" animation.toml {{UMBRIEL_MIGRATIONS['animation.toml']}}
          # A stale keybinds-vicinae.toml (old vicinae.src.pb installer
          # artifact) is deliberately NOT removed: the new root template
          # simply does not reference it.
    README: |
      # umbriel.etc.pb

      Etc-typed deployment (material under `/etc/opt/umbriel`) hosting the
      Umbriel user-config material and the Umbriel keybinding consumer
      profile. Live user config lives under `~/.config/umbriel` and is only
      modified by the user-scoped installer.

      ## Install / adopt (as the desktop user)

      ```sh
      ansible-playbook -i 'localhost,' -c local umbriel.etc.pb
      /etc/opt/umbriel/bin/install-user.sh
      ```

      `install-user.sh` seeds missing files from the staged material,
      migrates live files that still byte-match the previously managed
      `umbriel.user.pb` templates, and never overwrites user-edited text
      (a NOTE is printed instead). It then runs the generated
      `install-keybindings-umbriel.sh` host assembly, which rebuilds the
      managed area inside `~/.config/umbriel/config.toml`'s
      `include.files` array from the durable membership and validates the
      whole chain with the installed `umbriel` binary.

      After producers change, re-run their own `install-user.sh` (e.g.
      `/usr/local/src/vicinae-git/bin/install-user.sh`) to register updated
      bindings into this consumer.

      ## Files

      - `etc/config.toml` -- root include-chain template (baseline first,
        keybinding insertion area, optional personal fragments last)
      - `etc/keybinds-local.toml` -- personal chord overrides (no Mod+Grave:
        the consumer patch in this playbook owns that chord)
      - `etc/animation.toml` -- focus-navigation animation tuning
      - `etc/keybinding-umbriel.json` -- generated consumer profile
      - `bin/install-user.sh` -- seed/migrate + host assembly aggregate
      - `bin/install-keybindings-umbriel.sh` -- generated host installer
      - `bin/keybindings.mjs` -- generated shared keybindings runtime

      Requires node, jq, `block-in-file`, and `umbriel` on PATH at
      invocation time; none are installed by this deployment.
  tasks:
    - import_tasks: tasks/compfuzor.includes
