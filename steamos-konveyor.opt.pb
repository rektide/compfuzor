---
# DevL0rd/Konveyor on SteamOS (Plasma 6, Arch underneath) -- the "level 2"
# install. The ~1GB Qt/KDE toolchain never touches the tiny read-only root:
# it lives in an Arch chroot under this DIR on persistent /opt (home-backed),
# built against the host's exact Valve kwin (chroot pacman.conf is copied
# from the host, so both see the same pinned repo snapshot; kwin is installed
# version-locked to the running one). Only the finished artifacts land in
# /usr. First bootstrap costs ~2-3GB under DIR and a few minutes.
#
# steamos-update wipes /usr (and re-enables steamos-readonly) but /opt
# survives, so the post-update ritual is one command:
#
#   sudo bash bin/install.sh
#     # readonly disable -> archlane host deps -> ensure/sync chroot ->
#     # chroot build -> land plugins + kwinrc + widgets -> readonly enable
#
# To pick up new Konveyor commits: re-run this playbook (updates the
# checkout), then `sudo bash bin/install.sh` again. Game Mode/gamescope is
# untouched; this shapes desktop mode only.
#
# Host rootfs cost stays tiny: git, arch-install-scripts (pacstrap), jq and
# python-dbus (the widget collector service). Everything else is chroot-side.
#
# Env overrides: STEAMOS_KONVEYOR_USER (desktop user, default: SUDO_USER or
# `deck`), STEAMOS_KONVEYOR_READONLY=keep (leave the root writable after
# landing, for iteration).
- hosts: all
  vars:
    TYPE: steamos-konveyor
    INSTANCE: main
    REPO: https://github.com/DevL0rd/Konveyor
    GIT_SUBMODULES: True
    # host-side only; the build deps live in the chroot (install-chroot.sh)
    ARCH_PKGS:
      - git
      - arch-install-scripts
      - jq # widget collector service
      - python-dbus # widget collector service
    BINS:
      # body of the install.sh compositor: runs before the lanes
      - name: install.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo: sudo bash ${DIR}/bin/install.sh" >&2; exit 1; }
          command -v steamos-readonly >/dev/null 2>&1 \
              || { echo "steamos-konveyor: not a SteamOS host (no steamos-readonly)" >&2; exit 1; }
          pacman -Q kwin >/dev/null 2>&1 \
              || { echo "steamos-konveyor: kwin not installed?" >&2; exit 1; }
          steamos-readonly disable
      # main lane: ensure the dev chroot exists and matches the host kwin
      - name: install-chroot.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo (or via bin/install.sh)" >&2; exit 1; }
          CHROOT="${DIR}/archroot"
          HOST_KWIN="$(pacman -Q kwin | awk '{print $2}')"
          echo "host kwin: ${HOST_KWIN}"

          if [ ! -d "${CHROOT}/usr" ]; then
              echo "bootstrapping dev chroot at ${CHROOT} (a few minutes)"
              mkdir -p "${CHROOT}"
              # no -c: package cache stays inside the chroot (on /opt), not
              # on the host rootfs
              pacstrap "${CHROOT}" base
          fi

          # both sides see the host's pinned Valve snapshot: copy the host's
          # pacman.conf (+ includes) and sync dbs into the chroot
          install -Dm644 /etc/pacman.conf "${CHROOT}/etc/pacman.conf"
          if [ -d /etc/pacman.d ]; then
              mkdir -p "${CHROOT}/etc/pacman.d"
              cp -a /etc/pacman.d/. "${CHROOT}/etc/pacman.d/"
          fi
          mkdir -p "${CHROOT}/var/lib/pacman/sync"
          cp -a /var/lib/pacman/sync/. "${CHROOT}/var/lib/pacman/sync/" 2>/dev/null || true
          arch-chroot "${CHROOT}" pacman -Sy --noconfirm

          # upstream ARCH_PACKAGES (build deps) live here, not on the host
          arch-chroot "${CHROOT}" pacman -S --needed --noconfirm \
              base-devel cmake ninja git extra-cmake-modules \
              qt6-base qt6-declarative kglobalaccel kconfig kcolorscheme \
              knotifications kcoreaddons ki18n libxkbcommon python-dbus \
              kirigami layer-shell-qt kcmutils kirigami-addons kdeclarative \
              kservice kdecoration kwindowsystem vulkan-headers \
              vulkan-icd-loader wayland libepoxy libdrm python jq curl \
              openssh glib2 libkscreen qt6-tools kpackage
          # version-lock kwin to the running host build (ABI match)
          arch-chroot "${CHROOT}" pacman -S --needed --noconfirm "kwin=${HOST_KWIN}"

          CHROOT_KWIN="$(arch-chroot "${CHROOT}" pacman -Q kwin | awk '{print $2}')"
          if [ "${CHROOT_KWIN}" != "${HOST_KWIN}" ]; then
              echo "chroot kwin ${CHROOT_KWIN} != host kwin ${HOST_KWIN}." >&2
              echo "The repo snapshot moved past the running image:" >&2
              echo "run steamos-update, then sudo bash ${DIR}/bin/install.sh again." >&2
              exit 1
          fi
          echo "chroot ready (kwin ${CHROOT_KWIN})"
      # standalone rebuild (no landing, no readonly flip): for iteration
      - name: build.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
          CHROOT="${DIR}/archroot"
          BUILDS="${DIR}/builds/konveyor"
          STAGE="${DIR}/stage"
          [ -d "${CHROOT}/usr" ] || { echo "no chroot yet: sudo bash ${DIR}/bin/install-chroot.sh first" >&2; exit 1; }
          mkdir -p "${BUILDS}" "${STAGE}" "${CHROOT}/src" "${CHROOT}/build" "${CHROOT}/stage"
          mountpoint -q "${CHROOT}/src" || mount --bind "${DIR}/repo" "${CHROOT}/src"
          mountpoint -q "${CHROOT}/build" || mount --bind "${BUILDS}" "${CHROOT}/build"
          mountpoint -q "${CHROOT}/stage" || mount --bind "${STAGE}" "${CHROOT}/stage"
          cleanup() {
              umount "${CHROOT}/src" "${CHROOT}/build" "${CHROOT}/stage" 2>/dev/null || true
          }
          trap cleanup EXIT
          arch-chroot "${CHROOT}" cmake -S /src -B /build -G Ninja \
              -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr \
              -DKONVEYOR_BUILD_TESTS=OFF
          arch-chroot "${CHROOT}" cmake --build /build
          rm -rf "${STAGE:?}/"*
          arch-chroot "${CHROOT}" cmake --install /build --prefix /stage
          echo "built; staged tree at ${STAGE}/usr (land via sudo bash ${DIR}/bin/install-konveyor.sh)"
      # main lane: land the staged artifacts into /usr and activate
      - name: install-konveyor.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo (or via bin/install.sh)" >&2; exit 1; }
          STAGE="${DIR}/stage"
          [ -f "${STAGE}/usr/bin/konveyor" ] || bash "${DIR}/bin/build.sh"
          DESKTOP_USER="${STEAMOS_KONVEYOR_USER:-${SUDO_USER:-deck}}"
          PLUGIN_DIR="/usr/lib/qt6/plugins/kwin/effects/plugins"
          STATE_DIR="/usr/share/konveyor"
          id="$(date +%s)"

          as_user() {
              _uid="$(id -u "${DESKTOP_USER}")"
              _home="$(getent passwd "${DESKTOP_USER}" | cut -d: -f6)"
              runuser -u "${DESKTOP_USER}" -- \
                  env HOME="${_home}" USER="${DESKTOP_USER}" LOGNAME="${DESKTOP_USER}" \
                  XDG_RUNTIME_DIR="/run/user/${_uid}" \
                  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${_uid}/bus" "$@"
          }

          # 1) land the staged tree (bin/konveyor, share/konveyor, ...),
          #    then swap the two effect plugins for timestamped copies --
          #    exactly upstream install_files() + install_versioned_plugin()
          cp -a "${STAGE}/usr/." /usr/
          rm -f "${PLUGIN_DIR}/konveyor_effect.so" "${PLUGIN_DIR}/process_monitor_telemetry.so"
          install -Dm755 "${STAGE}${PLUGIN_DIR}/konveyor_effect.so" \
              "${PLUGIN_DIR}/konveyor_effect_${id}.so"
          install -Dm755 "${STAGE}${PLUGIN_DIR}/process_monitor_telemetry.so" \
              "${PLUGIN_DIR}/process_monitor_telemetry_${id}.so"
          mkdir -p "${STATE_DIR}"
          printf 'konveyor_effect_%s\n' "${id}" > "${STATE_DIR}/plugin-id"
          printf 'process_monitor_telemetry_%s\n' "${id}" > "${STATE_DIR}/telemetry-plugin-id"

          # 2) drop previous versions and their kwinrc keys
          for f in "${PLUGIN_DIR}"/konveyor_effect_*.so "${PLUGIN_DIR}"/process_monitor_telemetry_*.so; do
              [ -e "$f" ] || continue
              base="$(basename "$f" .so)"
              case "$base" in
                  "konveyor_effect_${id}"|"process_monitor_telemetry_${id}") ;;
                  *) rm -f "$f" ;;
              esac
          done
          as_user kwriteconfig6 --file kwinrc --group Plugins --key konveyor_effectEnabled false
          as_user kwriteconfig6 --file kwinrc --group Plugins --key "konveyor_effect_${id}Enabled" true
          as_user kwriteconfig6 --file kwinrc --group Plugins --key "process_monitor_telemetry_${id}Enabled" true
          _uh="$(getent passwd "${DESKTOP_USER}" | cut -d: -f6)"
          for key in $(grep -hoE '^(konveyor_effect|process_monitor_telemetry)[A-Za-z0-9_]*Enabled' \
                  "${_uh}/.config/kwinrc" 2>/dev/null | sort -u); do
              case "$key" in
                  "konveyor_effect_${id}Enabled"|"process_monitor_telemetry_${id}Enabled"|"konveyor_effectEnabled") ;;
                  *) as_user kwriteconfig6 --file kwinrc --group Plugins --key "$key" --delete ;;
              esac
          done

          # 3) live-activate (best effort without qdbus6: log out/in)
          if command -v qdbus6 >/dev/null 2>&1; then
              as_user qdbus6 org.kde.KWin /KWin reconfigure || true
              as_user qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect "konveyor_effect_${id}" || true
              echo "Konveyor loaded live -- press Super+K for the shortcut cheatsheet."
          else
              echo "qdbus6 not present: log out and back in to start Konveyor."
          fi

          # 4) widgets (user-level: ~/.local/share/konveyor/widgets + the
          #    collector user service); no plasma restart, they load next login
          as_user env KONVEYOR_WIDGETS_SOURCE="${DIR}/repo/widgets" "${DIR}/repo/widgets/install.sh" --no-restart

          if [ "${STEAMOS_KONVEYOR_READONLY:-}" != "keep" ]; then
              steamos-readonly enable
          fi
          echo "done. Log out/in if widgets look stale; Game Mode is untouched."
      # interactive shell in the dev chroot for debugging the build env
      - name: chroot-shell.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
          CHROOT="${DIR}/archroot"
          BUILDS="${DIR}/builds/konveyor"
          [ -d "${CHROOT}/usr" ] || { echo "no chroot yet: sudo bash ${DIR}/bin/install-chroot.sh first" >&2; exit 1; }
          mkdir -p "${BUILDS}" "${CHROOT}/src" "${CHROOT}/build" "${CHROOT}/stage"
          mountpoint -q "${CHROOT}/src" || mount --bind "${DIR}/repo" "${CHROOT}/src"
          mountpoint -q "${CHROOT}/build" || mount --bind "${BUILDS}" "${CHROOT}/build"
          mountpoint -q "${CHROOT}/stage" || mount --bind "${DIR}/stage" "${CHROOT}/stage"
          trap 'umount "${CHROOT}/src" "${CHROOT}/build" "${CHROOT}/stage" 2>/dev/null || true' EXIT
          arch-chroot "${CHROOT}" bash
      - name: konveyor-status.sh
        content: |
          CHROOT="${DIR}/archroot"
          PLUGIN_DIR="/usr/lib/qt6/plugins/kwin/effects/plugins"
          echo "host kwin:   $(pacman -Q kwin 2>/dev/null || echo missing)"
          if [ -d "${CHROOT}/usr" ]; then
              echo "chroot kwin: $(arch-chroot "${CHROOT}" pacman -Q kwin 2>/dev/null || echo missing)"
          else
              echo "chroot kwin: no chroot (${CHROOT})"
          fi
          echo "installed plugins:"
          ls -1 "${PLUGIN_DIR}"/konveyor_effect_*.so "${PLUGIN_DIR}"/process_monitor_telemetry_*.so 2>/dev/null \
              | xargs -r -n1 basename || true
      - name: uninstall-konveyor.sh
        content: |
          set -e
          [ "$(id -u)" -eq 0 ] || { echo "run with sudo" >&2; exit 1; }
          steamos-readonly disable
          DESKTOP_USER="${STEAMOS_KONVEYOR_USER:-${SUDO_USER:-deck}}"
          PLUGIN_DIR="/usr/lib/qt6/plugins/kwin/effects/plugins"
          STATE_DIR="/usr/share/konveyor"
          BUILDS="${DIR}/builds/konveyor"
          as_user() {
              _uid="$(id -u "${DESKTOP_USER}")"
              _home="$(getent passwd "${DESKTOP_USER}" | cut -d: -f6)"
              runuser -u "${DESKTOP_USER}" -- \
                  env HOME="${_home}" USER="${DESKTOP_USER}" LOGNAME="${DESKTOP_USER}" \
                  XDG_RUNTIME_DIR="/run/user/${_uid}" \
                  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${_uid}/bus" "$@"
          }
          # restore KDE shortcuts Konveyor had taken over (best effort)
          as_user konveyor restore-shortcuts || true
          # widgets + collector service
          as_user "${DIR}/repo/widgets/uninstall.sh" || true
          # files from the cmake manifest (what landed from stage/)
          if [ -f "${BUILDS}/install_manifest.txt" ]; then
              while IFS= read -r f; do
                  [ -n "$f" ] && rm -f "$f"
              done < "${BUILDS}/install_manifest.txt"
          fi
          rm -f "${PLUGIN_DIR}"/konveyor_effect_*.so "${PLUGIN_DIR}"/process_monitor_telemetry_*.so
          rm -rf "${STATE_DIR}" /usr/lib/konveyor
          _uh="$(getent passwd "${DESKTOP_USER}" | cut -d: -f6)"
          for key in $(grep -hoE '^(konveyor_effect|process_monitor_telemetry)[A-Za-z0-9_]*Enabled' \
                  "${_uh}/.config/kwinrc" 2>/dev/null | sort -u); do
              as_user kwriteconfig6 --file kwinrc --group Plugins --key "$key" --delete
          done
          if command -v qdbus6 >/dev/null 2>&1; then
              as_user qdbus6 org.kde.KWin /KWin reconfigure || true
          fi
          steamos-readonly enable
          echo "Konveyor removed (chroot and checkout kept under ${DIR}; log out/in to finish)."
  tasks:
    - import_tasks: tasks/compfuzor.includes
