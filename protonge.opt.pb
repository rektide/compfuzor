---
- hosts: all
  vars:
    TYPE: protonge
    INSTANCE: main
    # GE-Proton (GloriousEggroll's Proton build) for Steam, provisioned as a
    # mise tool through the mise2 deployment's isolated config root
    # (mise2.opt.pb). This playbook contributes exactly one tool pin to
    # mise2's config and owns nothing else there.
    #
    # Integration map -- this tool has NO shell/env surface at all (no shims,
    # no STEAM_EXTRA_COMPAT_TOOL_PATHS, no zim channel):
    #   plugin    augustobmoura/asdf-protonge, an asdf-backend plugin. mise's
    #             data root is shared (mise2 isolates only the config root),
    #             so the plugin and install payload are shared with any other
    #             mise deployment; only the pin is mise2-scoped. The
    #             mise-plugins/mise-protonge fork is a stale 2024-11 snapshot
    #             of this same plugin; upstream stays maintained.
    #   payload   Steam's compatibilitytools.d: the plugin downloads the
    #             GE-Proton release (tarball + sha512sum from GitHub),
    #             extracts it there, and symlinks mise's installs entry at
    #             the extracted dir. Steam scans compatibilitytools.d
    #             natively -- restart Steam, then pick the tool per game.
    #   pin       `mise use --global` under MISE_CONFIG_DIR, re-resolving
    #             `mise latest` on every lane run (track-latest: no fixed
    #             version lives in this playbook).
    # The render is inert on purpose: no TOOL_VERSIONS/MISE_VERSIONS (their
    # build-mise.sh would run `mise install` during the render lane, before
    # the plugin exists). All mise interaction is in the operator-run
    # install-user lane below.
    #
    # asdf coexistence: the retired(ing) asdf deployment
    # (~/.asdf/installs/protonge/* -> compatibilitytools.d) can keep pointing
    # at the same payload; nothing here removes it. Do NOT run
    # `asdf uninstall protonge <ver>` while mise manages that version -- the
    # plugin's uninstall removes the compat-dir payload both managers share.
    protonge_plugin_url: https://github.com/augustobmoura/asdf-protonge
    # mise2 config root (mirrors mise2.opt.pb; override via MISE2_CONFIG_DIR).
    mise2_config_dir: "${XDG_CONFIG_HOME:-$HOME/.config}/mise2/config"
    # Steam's compat root follows the plugin's own resolution: STEAM_ROOT
    # (default ~/.steam/root, here -> ~/.steam/debian-installation). Override
    # via PROTONGE_STEAM_COMPAT_DIR for e.g. flatpak Steam
    # (~/.var/app/com.valvesoftware.Steam/data/Steam/compatibilitytools.d).
    protonge_steam_root: "${STEAM_ROOT:-$HOME/.steam/root}"
    protonge_steam_compat_dir: "${PROTONGE_STEAM_COMPAT_DIR:-${STEAM_ROOT:-$HOME/.steam/root}/compatibilitytools.d}"
    ENV_LIST:
      - protonge_plugin_url
      - protonge_steam_root
      - protonge_steam_compat_dir
      - mise2_config_dir
    STATUSES:
      - status-protonge.sh
    BINS:
      # Operator lane: resolve latest GE-Proton, adopt or install it, pin it
      # in mise2's global config. Idempotent: re-running with no new release
      # is a no-op; a new release downloads, symlinks, and re-pins.
      - name: install-user.sh
        basedir: False
        content: |
          set -e
          # Deferred defaults in the rendered vars carry their own env
          # overrides (STEAM_ROOT, PROTONGE_STEAM_COMPAT_DIR, MISE2_CONFIG_DIR).
          steam_root="{{protonge_steam_root}}"
          steam_compat="{{protonge_steam_compat_dir}}"
          config_dir="{{mise2_config_dir}}"
          export ASDF_PROTONGE_STEAM_COMPAT_DIR="$steam_compat"
          # MISE_CONFIG_DIR isolates only the config root; plugin and payload
          # live in the shared data root either way.
          _mise() { MISE_CONFIG_DIR="$config_dir" mise "$@"; }

          if [ ! -d "$steam_root" ]; then
            echo "install-user: steam root $steam_root not found; set STEAM_ROOT/PROTONGE_STEAM_COMPAT_DIR for a non-default Steam" >&2
            exit 1
          fi

          if ! mise plugin list 2>/dev/null | grep -qx protonge; then
            mise plugin add protonge "${PROTONGE_PLUGIN_URL:-{{protonge_plugin_url}}}"
          fi

          latest="$(mise latest protonge)"
          installs_root="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/protonge"
          installs_path="$installs_root/$latest"

          # Adopt a compat-dir payload that already exists (hand-installed,
          # or from the asdf era) instead of tripping the plugin's
          # already-installed refusal: mirror bin/install's layout -- the
          # version dir is real, containing a compat-dir symlink at the
          # extracted entry (which may be arch-suffixed, e.g. -x86_64).
          if [ ! -e "$installs_path" ]; then
            payload=""
            for candidate in "$steam_compat/$latest" "$steam_compat/$latest"-*; do
              [ -d "$candidate" ] || continue
              if [ -n "$payload" ]; then
                echo "install-user: ambiguous compat entries for $latest under $steam_compat; refusing to adopt" >&2
                exit 1
              fi
              payload="$candidate"
            done
            if [ -n "$payload" ]; then
              mkdir -p "$installs_path"
              ln -s "$payload" "$installs_path/compat-dir"
              echo "install-user: adopted existing $payload as $installs_path/compat-dir"
            fi
          fi

          mkdir -p "$config_dir"
          # use --global installs missing versions, then records the pin.
          _mise use --global "protonge@$latest"

          echo
          echo "install-user: pinned protonge@$latest in $config_dir"
          echo "install-user: installed versions:"
          _mise ls protonge || true
          echo "install-user: restart Steam if it is running, then enable per game:"
          echo "install-user:   Properties -> Compatibility -> Force the use of a specific Steam Play tool"
      - name: status-protonge.sh
        basedir: False
        content: |
          status=0
          steam_compat="{{protonge_steam_compat_dir}}"
          config_dir="{{mise2_config_dir}}"
          installs_root="${MISE_DATA_DIR:-$HOME/.local/share/mise}/installs/protonge"
          _mise() { MISE_CONFIG_DIR="$config_dir" mise "$@"; }

          if ! mise plugin list 2>/dev/null | grep -qx protonge; then
            echo "protonge: mise plugin missing (run {{DIR}}/bin/install-user.sh)"
            status=1
          else
            echo "protonge: latest available: $(mise latest protonge 2>/dev/null || echo '?')"
            echo "protonge: installed (mise): $(_mise ls protonge 2>/dev/null | tr '\n' ' ')"
          fi

          if [ -f "$config_dir/config.toml" ] && grep -q '^protonge[[:space:]]*=' "$config_dir/config.toml"; then
            echo "protonge: mise2 pin: $(grep '^protonge[[:space:]]*=' "$config_dir/config.toml")"
          else
            echo "protonge: no mise2 pin in $config_dir/config.toml (run {{DIR}}/bin/install-user.sh)"
            status=1
          fi

          if [ -d "$steam_compat" ]; then
            for entry in "$steam_compat"/*; do
              [ -e "$entry" ] || continue
              name="$(basename "$entry")"
              target="$(readlink -f "$entry")"
              managed="unmanaged"
              for cdlink in "$installs_root"/*/compat-dir; do
                [ -L "$cdlink" ] || continue
                if [ "$(readlink -f "$cdlink")" = "$target" ]; then
                  managed="mise-managed"
                fi
              done
              echo "protonge: compat: $name ($managed)"
            done
          else
            echo "protonge: compat dir missing: $steam_compat"
            status=1
          fi

          for dir in "$installs_root"/*; do
            [ -d "$dir" ] || continue
            link="$dir/compat-dir"
            if [ -L "$link" ] && [ ! -e "$link" ]; then
              echo "protonge: broken install link: $link"
              status=1
            fi
          done
          exit "$status"
  tasks:
    - import_tasks: tasks/compfuzor.includes
