---
- hosts: all
  vars:
    TYPE: gdm-no-suspend
    INSTANCE: main
    PKGS:
      - crudini
    ENV:
      dest: /etc/gdm3/greeter.dconf-defaults
      # gen_link transport: clobber via cp instead of merge (destructive on a
      # shared conffile — loses Debian's defaults). Opt-in, not default.
      # link_copy: true
      # gen_link phase: route the deploy into build-link.sh instead of
      # install-link.sh (compile-time; gen_link would emit the body there).
      # link_phase: build
    ETC_FILES:
      - name: no-suspend.conf
        content: |
          [org/gnome/settings-daemon/plugins/power]
          sleep-inactive-ac-type = 'nothing'
          sleep-inactive-battery-type = 'nothing'
          sleep-inactive-ac-timeout = 0
          sleep-inactive-battery-timeout = 0

          [org/gnome/desktop/session]
          idle-delay = uint32 0
    BINS:
      - name: build-link.sh
        content: |
          if [ -n "${COMPFUZOR_LINK_BYPASS:-}" ]; then
            if [ -z "${COMPFUZOR_QUIET:-}" ] && { [ -z "${V+x}" ] || [ "$V" != 0 ]; }; then
              echo "link: COMPFUZOR_LINK_BYPASS set, skipping build" >&2
            fi
            exit 0
          fi
          test -f "$DIR/etc/no-suspend.conf"
      - name: install-link.sh
        content: |
          if [ -n "${COMPFUZOR_LINK_BYPASS:-}" ]; then
            if [ -z "${COMPFUZOR_QUIET:-}" ] && { [ -z "${V+x}" ] || [ "$V" != 0 ]; }; then
              echo "link: COMPFUZOR_LINK_BYPASS set, skipping deploy" >&2
            fi
            exit 0
          fi
          if [ -n "${LINK_COPY:-}" ]; then
            sudo cp -fv "$DIR/etc/no-suspend.conf" "$DEST"
          else
            sudo crudini --merge "$DEST" < "$DIR/etc/no-suspend.conf"
          fi
          sudo systemctl reload gdm
  tasks:
    - import_tasks: tasks/compfuzor.includes
