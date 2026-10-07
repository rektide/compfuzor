---
- hosts: all
  vars:
    PKGS:
      - crudini
    BINS:
      - name: install.sh
        content: |
          # absolute paths, rendered at generation: the January 2026 runs
          # died on unbound $DST/$DEST/$SRC (the wrapper sets -u and the
          # env never defined them uppercase)
          SRC="{{DIR}}/etc/main.conf"
          DST="/etc/bluetooth/main.conf"
          cp "$DST" "${DST}.bak.$(date +%s)"
          crudini --merge "$DST" < "$SRC"
          SRC="{{DIR}}/etc/input.conf"
          DST="/etc/bluetooth/input.conf"
          cp "$DST" "${DST}.bak.$(date +%s)"
          crudini --merge "$DST" < "$SRC"
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
