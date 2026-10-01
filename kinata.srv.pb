---
- hosts: all
  vars:
    TYPE: kanata
    INSTANCE: kinata
    # Third kanata instance owning ONLY the Kinesis Freestyle Edge RGB
    # (KB975, USB 29ea:0103; evdev "Kinesis Freestyle Edge RGB Keyboard",
    # seen as event1/event2 -- the number churns across replugs). kanata
    # 1.9 has no per-device keymaps on Linux, so Edge-specific semantics
    # get a device-scoped instance -- same pattern as
    # kanata-blueturn.srv.pb. Main (kanata.srv.pb) excludes the keyboard
    # node in the same change and keeps everything else it auto-detects:
    # the Edge's "Kinesis Freestyle Edge RGB Keyboard Consumer Control"
    # node (multimedia works natively on the RGB -- no kfreestyle2d
    # needed, unlike the Freestyle 2), the Keychron dongle, and the
    # various virtual keyboards.
    #
    # What this instance maps:
    #   caps -> tap-hold 100 100 esc lctl  (duplicated from main: the
    #           Edge left main's keymap when it got this instance)
    #   f21  -> lalt  (Game Bank hk5)
    #   f22  -> lmet  (Game Bank hk6)
    #
    # Game Bank keys are BLANK from the factory: they emit nothing until
    # SmartSet-programmed, so kanata-mediated mapping needs the keyboard
    # told to emit F21/F22 first. That on-board half is kinefolk's job
    # (~/src/kinefolk, SmartSet native control): two lines in the active
    # Profile's file in the "layouts" subfolder of the v-Drive
    # (SmartSet+F8 connects it):
    #   [hk5]>[f21]
    #   [hk6]>[f22]
    # then Refresh (SmartSet+Profile) or v-Drive disconnect; remaps only
    # run while the v-Drive is disconnected. Tokens per the RGB Direct
    # Programming Guide (Expansion Pack 2, 2023-05-24): [hk1]-[hk8]
    # positions, F13-F24 actions.
    #
    # Why kanata-mediated instead of on-board [hk5]>[lalt]/[hk6]>[lwin]:
    # semantics stay here -- versioned, live-reloadable, upgradable to
    # one-shot mods/tap-hold/layers without re-dipping the v-Drive; and
    # the Edge's Game Mode (SmartSet+F11, suppresses on-board Windows-key
    # actions) can't touch kanata's lmet output. Trade-off: hk5/hk6 do
    # nothing wherever kanata isn't running (BIOS, other machines).
    #
    # Reuses the packaged kanata package's static _kanata user (input
    # group) -- same shape as kanata-blueturn.srv.pb and
    # /usr/lib/systemd/system/kanata.service. SYSTEMD_ALIAS: false is
    # load-bearing: the -kinata name would otherwise alias to
    # kanata.service and fight the packaged unit.
    PKGS:
      - kanata
    ETC_PROP:
      mode: "0755"
    SYSTEMD_ALIAS: false
    SYSTEMD_UNITS:
      Description: Kanata remapper -- Kinesis Freestyle Edge RGB
      Documentation: https://github.com/jtroo/kanata
      Wants: modprobe@uinput.service
      After: modprobe@uinput.service
    SYSTEMD_SERVICES:
      Type: simple
      User: _kanata
      Group: _kanata
      SupplementaryGroups: input
      ExecStart: /usr/bin/kanata --cfg /etc/kanata/kinata.kbd
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
    LINKS:
      - src: "{{ETC}}/kanata.kbd"
        dest: /etc/kanata/kinata.kbd
        scope: system
        policy: replace
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            process-unmapped-keys yes
            ;; whole instance scoped to the Edge's keyboard node:
            ;; exact-name match (no regex); name from kanata's own
            ;; "registering" log line. The "... Consumer Control" node
            ;; is a different exact name and stays with main.
            linux-dev-names-include (
              "Kinesis Freestyle Edge RGB Keyboard"
            )
            ;; event nodes churn across replugs (event1/event2 seen);
            ;; stay up and let the /dev/input watcher pick it up
            linux-continue-if-no-devs-found yes
          )

          ;; f21/f22 arrive only after kinefolk programs the Game Bank
          ;; (hk5/hk6) to emit them -- until then those columns are
          ;; simply never pressed and stay harmless.
          (defsrc
            caps f21 f22
          )

          (deflayer base
            (tap-hold 100 100 esc lctl)
            lalt
            lmet
          )
  tasks:
    - import_tasks: tasks/compfuzor.includes
