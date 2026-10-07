---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: blueturn
    # Second kanata instance owning ONLY the iRig BlueTurn BLE footpedal
    # ("iRig BlueTurn Keyboard", 0005:0214:0002, public IK address
    # 00:A0:50:14:19:28): kanata 1.9 has no per-device keymaps on Linux
    # (definputdevices/device-history is macOS-only), but
    # linux-dev-names-include scopes a whole instance -- so the pedal
    # gets this daemon and kanata.srv.pb (main) excludes it, keeping
    # tap-hold pedal semantics off real keyboards. Mode 2 on the pedal
    # (select: hold RIGHT pedal while flipping power on): LEFT=pgup,
    # RIGHT=pgdn, both momentary -- tap LEFT pages back, hold LEFT
    # enters pedal-meta (tap RIGHT there = play/pause).
    #
    # CAVEAT kernel 7.1.0-debplus: hid-core drops the pedal's 7-byte
    # keyboard reports (uhid short-report regression; "Event data for
    # report 0 was too short (8 vs 7)" in dmesg; fixed in 7.1.4+/7.2,
    # backport cfc0d283d931). This instance runs and grabs the device,
    # but no keys arrive until a kernel with the fix -- unless
    # blueturn-hidbpf.etc.pb is applied: its device_event eBPF pad
    # (7->8 trailing zero, auto-attached per uhid instance via
    # udev-hid-bpf) restores pre-7.0 semantics on affected kernels.
    # Full story: design/blueturn/kernel-uhid-shortreport.general.md
    #
    # Consumes the _kanata identity kanata.srv.pb declares (sysusers
    # fragment; User=/Group=/SupplementaryGroups here, no declaration of
    # its own) and the kanata.src.pb binary at /usr/local/bin/kanata --
    # no PKGS: nothing here reinstalls the Debian package. Same sandbox
    # shape as the main unit, ExecStart pointed at our staged config
    # (linked into /etc/kanata/, which the sandbox binds read-only).
    # SYSTEMD_ALIAS: false stays load-bearing: the -blueturn name would
    # otherwise alias to kanata.service and fight the canonical unit
    # main owns.
    ETC_PROP:
      mode: "0755"
    SYSTEMD_ALIAS: false
    SYSTEMD_UNITS:
      Description: Kanata remapper -- iRig BlueTurn pedal
      Documentation: https://github.com/jtroo/kanata
      Wants: modprobe@uinput.service
      After: modprobe@uinput.service
    SYSTEMD_SERVICES:
      Type: simple
      User: _kanata
      Group: _kanata
      SupplementaryGroups: input
      ExecStart: /usr/local/bin/kanata --cfg /etc/kanata/blueturn.kbd
      # quoted so the unit carries an explicit Restart=no (a bare YAML
      # no is False, which the unit template drops); empty
      # CapabilityBoundingSet renders the packaged unit's line
      Restart: "no"
      CapabilityBoundingSet: ""
      DeviceAllow:
        - /dev/uinput rw
        - char-input
        - /dev/stdin
      DevicePolicy: strict
      PrivateDevices: true
      BindPaths: /dev/uinput
      BindReadOnlyPaths:
        - /dev/stdin
        - /dev/input/
        - /etc/kanata/
      InaccessiblePaths: /dev/shm
      LockPersonality: true
      NoNewPrivileges: true
      PrivateTmp: true
      PrivateNetwork: true
      PrivateUsers: true
      ProtectHome: true
      ProtectHostname: true
      ProtectKernelTunables: true
      ProtectKernelModules: true
      ProtectKernelLogs: true
      ProtectSystem: strict
      ProtectControlGroups: true
      RestrictAddressFamilies:
        - AF_AX25
        - ~AF_AX25
      RestrictNamespaces: true
      SystemCallArchitectures: native
      SystemCallErrorNumber: EPERM
      SystemCallFilter:
        - "@system-service"
        - "~@privileged"
        - "~@resources"
      RemoveIPC: true
      IPAddressDeny: any
      RestrictSUIDSGID: true
      RestrictRealtime: true
      MemoryDenyWriteExecute: true
      UMask: "0077"
    SYSTEMD_INSTALLS:
      WantedBy: default.target
    LINKS:
      - src: "{{ETC}}/kanata.kbd"
        dest: /etc/kanata/blueturn.kbd
        scope: system
        policy: replace
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        # write-once under KANATA_CONFIG_PRESERVE (see kanata.srv.pb):
        # cutover rerenders refresh everything else while existing
        # config bytes skip write; default false keeps renders
        # authoritative
        once: "{{ KANATA_CONFIG_PRESERVE | default(false) | bool }}"
        content: |
          (defcfg
            process-unmapped-keys yes
            ;; whole instance scoped to the pedal: exact-name match (no
            ;; regex); name from kanata's own "registering" log line. If
            ;; the pedal ever shows up under a different identity (e.g.
            ;; re-pairing before bonding -> "ADAPTER_95AB Keyboard"),
            ;; this include silently misses it.
            linux-dev-names-include (
              "iRig BlueTurn Keyboard"
            )
            ;; the pedal sleeps when idle: at boot (or after long idle)
            ;; zero matching devices exist -- keep running and let the
            ;; /dev/input watcher pick it up on reconnect
            linux-continue-if-no-devs-found yes
          )

          ;; pedal mode 2: LEFT=pgup RIGHT=pgdn (momentary, held while
          ;; pressed). tap LEFT = page back; hold LEFT (>=180ms) =
          ;; pedal-meta layer while held.
          (defsrc
            pgup pgdn
          )

          (deflayer base
            (tap-hold 180 180 pgup (layer-while-held pedal-meta))
            pgdn
          )

          (deflayer pedal-meta
            _
            pp
          )
  tasks:
    - import_tasks: tasks/compfuzor.includes
