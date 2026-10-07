---
- hosts: all
  vars:
    PKGS:
      - crudini
    ENV:
      src: "{{DIR}}/etc/main.conf"
      dest: "/etc/bluetooth/main.conf"
    BINS:
      - name: install.sh
        content: |
          cp "$DST" "${DST}.bak.$(date +%s)"
          crudini --merge "$DEST" < "$SRC"
          IN_SRC="{{DIR}}/etc/input.conf"
          IN_DEST="/etc/bluetooth/input.conf"
          cp "$IN_DEST" "${IN_DEST}.bak.$(date +%s)"
          crudini --merge "$IN_DEST" < "$IN_SRC"
    ETC_FILES:
      - name: main.conf
        content: |
          [General]
          Experimental = true
          PairableTimeout = 30
          FastConnectable = true
          # reconnect hardening (design/blueturn research; DasBen gist):
          # residual bearer drops self-heal instead of stranding the device
          # -- the Surface Dial was cycling 7-15 min drops through 2026-10-06.
          ReconnectAttempts = 7
          ReconnectIntervals = 1,2,4,8,16,32,64
          # power the adapter at boot so reconnects always have a controller
          AutoEnable = true
          [BR]
          LinkSupervisionTimeout = 64000
          [AVDTP]
          SessionMode = ertm
          StreamMode = streaming
      - name: input.conf
        content: |
          [General]
          # explicit: BlueZ HID sessions never idle-disconnect. the default
          # is 0, but pin it -- a distro default flip would present exactly
          # like the Dial's idle bearer drops.
          IdleTimeout = 0
  tasks:
    - import_tasks: tasks/compfuzor.includes
