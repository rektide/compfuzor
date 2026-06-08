---
- hosts: all
  vars:
    REPO: https://codeberg.org/debugloop/niri-autoselect-portal
    GO: True
    PKGS:
      - xdg-desktop-portal
      - pipewire
    SYSTEMD_SERVICE: True
    SYSTEMD_SCOPE: user
    SYSTEMD_INSTALL: user
    SYSTEMD_USERMODE: True
    SYSTEMD_UNITS:
      PartOf: graphical-session.target
    SYSTEMD_EXEC: /usr/local/bin/niri-autoselect-portal
    SYSTEMD_SERVICES:
      Type: dbus
      BusName: org.freedesktop.impl.portal.desktop.niri-autoselect
    SYSTEMD_INSTALLS:
      WantedBy: niri.service
    SYSTEMD_LINK: False
    SHARE_DIRS:
      - xdg-desktop-portal/portals
      - dbus-1/services
    SHARE_FILES:
      - name: xdg-desktop-portal/portals/niri-autoselect.portal
        content: |
          [portal]
          DBusName=org.freedesktop.impl.portal.desktop.niri-autoselect
          Interfaces=org.freedesktop.impl.portal.ScreenCast
      - name: dbus-1/services/org.freedesktop.impl.portal.desktop.niri-autoselect.service
        content: |
          [D-BUS Service]
          Name=org.freedesktop.impl.portal.desktop.niri-autoselect
          Exec=/usr/local/bin/niri-autoselect-portal
          SystemdService=niri-autoselect-portal.service
      - name: xdg-desktop-portal/niri-portals.conf
        content: |
          org.freedesktop.impl.portal.ScreenCast=niri-autoselect;
    BINS:
      # install-user.sh is the recommended installer: xdg-desktop-portal and
      # dbus-daemon both search XDG user directories, so system-level symlinks
      # are unnecessary. block-in-file --additive injects our ScreenCast line
      # into the existing niri-portals.conf without clobbering other entries.
      - name: install-user.sh
        basedir: False
        run: true
        content: |
          DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
          CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

          mkdir -p "$DATA/xdg-desktop-portal/portals" "$DATA/dbus-1/services" "$CONFIG/xdg-desktop-portal"

          ln -sfv "{{DIR}}/share/xdg-desktop-portal/portals/niri-autoselect.portal" "$DATA/xdg-desktop-portal/portals/"
          ln -sfv "{{DIR}}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.niri-autoselect.service" "$DATA/dbus-1/services/"

          PORTAL_CONF="$CONFIG/xdg-desktop-portal/niri-portals.conf"
          if [ ! -f "$PORTAL_CONF" ]; then
            SYSTEM_CONF="/usr/share/xdg-desktop-portal/niri-portals.conf"
            if [ -f "$SYSTEM_CONF" ]; then
              cp -v "$SYSTEM_CONF" "$PORTAL_CONF"
            else
              touch "$PORTAL_CONF"
            fi
          fi
          # TODO: use block-in-file --remove-line/--replace-line (bif-remove-line)
          # to replace any existing ScreenCast line instead of appending at EOF.
          block-in-file -n niri-autoselect-portal -a EOF -c "#" -i "{{DIR}}/share/xdg-desktop-portal/niri-portals.conf" -o "$PORTAL_CONF"
      - name: uninstall-user.sh
        basedir: False
        content: |
          DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
          CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}"

          rm -fv "$DATA/xdg-desktop-portal/portals/niri-autoselect.portal"
          rm -fv "$DATA/dbus-1/services/org.freedesktop.impl.portal.desktop.niri-autoselect.service"

          PORTAL_CONF="$CONFIG/xdg-desktop-portal/niri-portals.conf"
          block-in-file -n niri-autoselect-portal --remove-all -o "$PORTAL_CONF"
  tasks:
    - import_tasks: tasks/compfuzor.includes
