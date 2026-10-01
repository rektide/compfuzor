---
- hosts: all
  vars:
    TYPE: bluetooth-justworkrepair
    # BLE HID gadgets with amnesiac bond tables (here: the iRig BlueTurn
    # footpedal feeding kanata.srv.pb) lose or rotate their side of the
    # LTK: every wake is a *fresh* SMP pairing -- new keys each time --
    # and each wants a live agent confirmation that headless bluetoothd
    # cannot provide. The connection flaps and the evdev node kanata
    # grabbed appears/vanishes ("Failed to ungrab device"). main.conf
    # JustWorksRepairing lets bluetoothd accept a just-works repair
    # instead of nagging. This was a manual /etc/bluetooth/main.conf edit
    # (the "JustWorksRepair thing"); now declared here. Pairing itself
    # is runtime state, not config: wake the pedal, then in ONE
    # bluetoothctl session `agent on; default-agent; disconnect;
    # pair; trust` -- pairing dies without that session's agent.
    PKGS:
      - crudini
    BINS:
      - name: install.sh
        run: true
        become: true
        content: |
          SRC="{{ETC}}/main.conf"
          DST="/etc/bluetooth/main.conf"
          md5_before="$(md5sum "$DST"|cut -d' ' -f1)"
          crudini --merge "$DST" < "$SRC"
          md5_after="$(md5sum "$DST"|cut -d' ' -f1)"
          # crudini rewrites (mtime-bumps) even on no-op merges, so gate
          # the bluetoothd restart on content, not timestamps
          if [ "$md5_before" != "$md5_after" ]; then
            systemctl restart bluetooth.service
          fi
    ETC_FILES:
      - name: main.conf
        content: |
          [General]
          JustWorksRepairing = always
  tasks:
    - import_tasks: tasks/compfuzor.includes
