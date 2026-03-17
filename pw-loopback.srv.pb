---
- hosts: all
  vars:
    #SYSTEMD_SERVICE: True
    args:
      capture: "alsa_input.pci-0000_0b_00.4.analog-stereo"
      name: "loop-{{INSTANCE}}"
    argKeys:
      capture: "C"
      name: "n"
    SYSTEMD_UNIT:
      Description: Pipewire Loopback
      After: pipewire.service
      PartOf: pipewire.service
      BindsTo: pipewire.service
    SYSTEMD_SERVICES:
      Type: simple
      SyslogIdentifier: pw-loopback
      ExecStart: >-
        /usr/bin/pw-loopback
        {%- for key in args.keys() %}
        -{{ argKeys[key] }} "{{ args[key] }}"
        {%- endfor %}
    SYSTEMD_INSTALL:
      WantedBy: pipewire.service
      Alias: pw-looopback
    SYSTEMD_LINK: False
    # we want this globally avialable for anyone to install
    #SYSTEMD_SCOPE: user
    ENV: True
    BINS:
      # interesting desire here / what's the pattern: global "service" for each user to then install
      - name: install-user.sh
        content: |
          # {{SYSTEMD_SCOPE}}
          [ -n "$INSTALL_DIR" ] || INSTALL_DIR="$HOME/.config/systemd/user"
          mkdir -p $INSTALL_DIR
          ln -sf $(pwd)/etc/pw-loopback.service $INSTALL_DIR/
          systemctl --user enable pw-loopback.service
          systemctl --user start pw-loopback.service
  tasks:
    - import_tasks: tasks/compfuzor.includes
