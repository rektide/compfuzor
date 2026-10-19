---
# pw-eq-fiio — EQ scenario service: FiiO branch (preferred arrangement)
#
# Topology this asserts:
#   apps + line-in -> combine_sink (default) -> fan-out:
#     -> 4 hardware sinks raw
#     -> WEILIANG raw fan stream          (zero manually in pavucontrol)
#     -> eq_sink -> EQ bands -> WEILIANG  (the EQ'd FiiO feed)
#
# eq_sink is admitted into combine_sink's fan-out whitelist by NAME
# (see pipewire-virtual-sink.etc.pb). The global scenario deliberately
# uses the node name eq_global, which does NOT match that whitelist,
# so one combine config serves both scenarios without feedback loops.
#
# Switching: systemctl --user start pw-eq-fiio (Conflicts= stops
# pw-eq-global first — its ExecStop removes that conf and restarts the
# graph, then this service's ExecStart installs ours and restarts again;
# a switch costs two graph restarts by design). Neither service active
# (both stopped/disabled) = no-EQ state: confs removed, default sink
# combine_sink.
#
# The unit is a oneshot with RemainAfterExit: active = this scenario is
# installed. At session start (WantedBy=default.target) ExecStart
# re-asserts the scenario; pw-eq-activate skips the restart when the
# conf, default sink, and sibling-absence already match (idempotent).
#
# Curve lives in pw-eq.etc.pb's PW_EQ_BANDS / the activate --bands flag.
# Raw tooling: /etc/opt/pw-eq-main/bin/{pw-eq-gen.js,pw-eq-activate}.

- hosts: all
  vars:
    ETC_FILES:
      - name: pw-eq-fiio.service
        content: |
          [Unit]
          Description=PipeWire EQ scenario: FiiO branch (combine -> eq_sink -> FiiO)
          Conflicts=pw-eq-global.service
          After=pipewire.service wireplumber.service

          [Service]
          Type=oneshot
          RemainAfterExit=yes
          ExecStart=/etc/opt/pw-eq-fiio-main/bin/pw-eq-fiio --install
          ExecStop=/etc/opt/pw-eq-fiio-main/bin/pw-eq-fiio --off

          [Install]
          WantedBy=default.target
    BINS:
      # Scenario wrapper — sets PW_EQ_* env for the shared pw-eq-activate
      # and execs it. Thin by design: all logic lives in pw-eq.etc.pb's
      # shared toolkit.
      - name: pw-eq-fiio
        src: pw-eq-fiio
        helpers: false

      # User-scope install in the pw-loopback.srv.pb tradition: link the
      # unit into ~/.config/systemd/user and enable it. Deliberately does
      # NOT start the service — starting switches the live graph.
      - name: install-user.sh
        content: |
          #!/bin/bash
          set -euo pipefail
          [ -n "${INSTALL_DIR:-}" ] || INSTALL_DIR="$HOME/.config/systemd/user"
          mkdir -p "$INSTALL_DIR"
          ln -sf "$(pwd)/etc/pw-eq-fiio.service" "$INSTALL_DIR/"
          systemctl --user daemon-reload
          systemctl --user enable pw-eq-fiio.service
          echo "pw-eq-fiio.service enabled."
          echo "Activate now with: systemctl --user start pw-eq-fiio"
    ENV:
      ETC: "{{ETC}}"
      APP: pipewire
  tasks:
    - import_tasks: tasks/compfuzor.includes
