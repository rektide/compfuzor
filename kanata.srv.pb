---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: main
    # kanata: the maintained successor to interception-tools (Debian
    # removed the latter from sid 2026-06-26). One daemon replaces the
    # whole udevmon | intercept | caps2esc | uinput pipeline; deployed on
    # workhorse 2026-09-30, displacing interception-tools-main.service
    # (whose trixie packages ride the debian-stable pin-100 backstop).
    #
    # Source lane (design/kanata-source/): kanata.src.pb builds the
    # binary (RUST_COPY real file at /usr/local/bin/kanata -- tcp_server
    # is in its feature set, unlike Debian 1.9.0+ds-1), so no PKGS here:
    # this playbook plus its two helpers own the whole deployment once
    # the package leaves.
    #
    # THE canonical unit: SYSTEMD_SERVICE: kanata renders kanata.service
    # -- the packaged unit's name, deliberately, so the source lane
    # replaces it in place instead of fielding a kanata-main.service
    # next to it. SYSTEMD_ALIAS: false is the same load-bearing opt-out
    # the helpers carry: nothing of ours may alias onto kanata.service
    # from a second name. (A pre-migration kanata-main.service artifact
    # sits in ETC from an earlier experiment; it is unlinked and inert,
    # and gets cleaned up at cutover rather than here.)
    SYSTEMD_SERVICE: kanata
    SYSTEMD_ALIAS: false
    # Single declarer of the shared _kanata identity. The Debian package
    # provisioned it dynamically (useradd --system in its postinst: uid/
    # gid landed at 990/985 here, plus input membership); SYSUSERS pins
    # both ids in sysusers.d(5)'s uid:gid form so this host's account
    # survives the package verbatim -- systemd-sysusers never modifies
    # existing names, so against the live account this is a no-op, and
    # fresh hosts converge on the same ids. (No separate g spec: the
    # renderer declares one line per name, and u already implies the
    # same-name primary group.) kanata-blueturn.srv.pb and kinata.srv.pb
    # consume the identity (User=/Group=/SupplementaryGroups: input)
    # without declaring it. home/shell stay at the sysusers defaults
    # (/nonexistent, nologin): the live account's /home/_kanata + zsh
    # predate this declaration and are not touched.
    SYSTEMD_SYSUSER: True
    SYSUSERS:
      - {name: _kanata, id: "990:985", comment: Kanata daemon}
      - {name: _kanata, member: input}
    # mirrors the retired /usr/lib/systemd/system/kanata.service
    # (same hardening schema as the helpers), with the static user/
    # group + input access spelled out and ExecStart swapped to the
    # source binary. Restart: no renders empty (falsy) -- systemd's
    # default -- matching the packaged Restart=no policy.
    SYSTEMD_UNITS:
      Description: Kanata keyboard remapper
      Documentation: https://github.com/jtroo/kanata
      Wants: modprobe@uinput.service
      After: modprobe@uinput.service
    SYSTEMD_SERVICES:
      Type: simple
      User: _kanata
      Group: _kanata
      SupplementaryGroups: input
      ExecStart: /usr/local/bin/kanata --cfg /etc/kanata/config.kbd
      Restart: no
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
    # the unit's _kanata user must traverse ETC and read the config
    # (0770/0660 default DIRMODE/FILEMODE block it -- same lesson as
    # apt-cacher-rs); config is staged in ETC and linked over
    # /etc/kanata/config.kbd -- the keyd pattern, unchanged
    ETC_PROP:
      mode: "0755"
    LINKS:
      - src: "{{ETC}}/kanata.kbd"
        dest: /etc/kanata/config.kbd
        scope: system
        policy: replace
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            process-unmapped-keys yes
            ;; the iRig BlueTurn pedal has its own kanata instance
            ;; (kanata-blueturn.srv.pb): exclude it here so the shared
            ;; keymap never applies pedal semantics (e.g. tap-hold on
            ;; pgup) to real keyboards. Exact-name match, no regex --
            ;; name as printed by kanata's "registering" lines.
            ;;
            ;; the Freestyle Edge RGB keyboard node likewise moved to
            ;; its own instance (kinata.srv.pb: Game Bank hk5/hk6 map
            ;; f21/f22 -> lalt/lmet + this same caps remap). Its
            ;; "Kinesis Freestyle Edge RGB Keyboard Consumer Control"
            ;; node is a different exact name and stays here --
            ;; multimedia passes through untouched (defsrc is caps
            ;; only, process-unmapped-keys yes).
            linux-dev-names-exclude (
              "iRig BlueTurn Keyboard"
              "Kinesis Freestyle Edge RGB Keyboard"
            )
          )

          (defsrc
            caps
          )

          (deflayer base
            (tap-hold 100 100 esc lctl)
          )

          ;; BlueTurn notes (2026-10-01, all verified on-device):
          ;; identity: "iRig BlueTurn Keyboard", bus 0005 (BT), vendor
          ;; 0214 (IK Multimedia), product 0002 -- from its PUBLIC
          ;; address 00:A0:50:14:19:28 once bonded (the earlier
          ;; "ADAPTER_95AB Keyboard" / vendor 07d7 random-address
          ;; identity was the pre-bonding era).
          ;; bonding: JustWorksRepairing=always lives in
          ;; bluetooth-justworkrepair.etc.pb; pairing needs ONE
          ;; bluetoothctl session (agent on; default-agent; disconnect;
          ;; pair; trust) -- pairing dies without that session's agent.
          ;; report drops: kernel 7.1 hid-core drops its 7-byte keyboard
          ;; reports ("Event data for report 0 was too short (8 vs 7)",
          ;; uhid regression, fixed 7.2 / backport cfc0d283d931) --
          ;; pedal keys stay dead until then:
          ;; design/blueturn/blueturn-linux-research.general.md
          ;; modes (select at power-on: hold LEFT=1, RIGHT=2, BOTH=3):
          ;; 1 LEFT=up RIGHT=down; 2 LEFT=pgup RIGHT=pgdn; 3 LEFT=left
          ;; RIGHT=right. momentary keys; no long/short distinction.
          ;; half-attached bearer ("Connected" but no HID node, silent
          ;; ATT death ~10min): btusb adapter autosuspend -- off entirely
          ;; since 2026-10 via kernel-usb-autosuspend.etc.pb (the prior
          ;; always-on rule never parsed, let alone pinned anything);
          ;; zombie links clear with
          ;; a controller power cycle (bluetoothctl power off; on).
  tasks:
    - import_tasks: tasks/compfuzor.includes
