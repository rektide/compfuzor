---
# umbriel.user.pb -- user-level Umbriel compositor configuration.
#
# Owns the ROOT user config, ~/.config/umbriel/config.toml, which is a thin
# [include] chain: it layers the system default (installed by umbriel.src.pb
# to /usr/local/share/umbriel/config.toml) plus optional fragments contributed
# by other entries (currently vicinae.src.pb's keybinds-vicinae.toml symlink).
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
#     built-in defaults. That merge is exactly what this chain relies on:
#     the system default supplies the baseline set, later includes override
#     individual chords, and any keybinds a fragment redefines win.
#   * [include] may appear at most once per TOML file, so this root file is
#     the single place the chain is declared; fragments attach to it as
#     optional includes, not by editing this file.
#
# Division of labor across compfuzor entries:
#   umbriel.src.pb  -- source build; installs /usr/local/share/umbriel/
#                      config.toml (the chain's baseline) and the binaries
#   vicinae.src.pb  -- keybinds-vicinae.toml fragment (Mod+Space launcher,
#                      Mod+Slash window switcher) symlinked into
#                      ~/.config/umbriel/ by its install-umbriel.sh
#   this entry      -- the root include chain itself
#
# USERMODE: no sudo; everything lands under ~/.config and ~/.local/opt.
# Idempotent: re-running re-renders config.toml content-in-place. The
# vicinae symlink is vicinae.src.pb's artifact and is deliberately not
# touched here.

- hosts: all
  user: rektide
  vars:
    TYPE: umbriel
    # NAME defaults to TYPE-INSTANCE (instance "main" is implicit), which
    # would render ETC to ~/.config/umbriel-main/. Pin NAME so the config
    # lands where umbriel actually reads it: ~/.config/umbriel/.
    NAME: umbriel
    USERMODE: True
    ETC_FILES:
      # Rendered to {{ETC}}/config.toml == ~/.config/umbriel/config.toml.
      - config.toml
  tasks:
    # Modern form of `include: tasks/compfuzor.includes type="opt"`: this
    # box's ansible-core (2.21) removed bare `include:`, while older
    # playbooks in the repo still carry it. `vars: type: opt` feeds the
    # type-derived DIR/ETC paths the same way the old kwarg did.
    - import_tasks: tasks/compfuzor.includes
      vars:
        type: opt
