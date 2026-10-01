---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    TYPE: kanata
    INSTANCE: a-pedal
    ETC: "{{ ETCS_DIR }}/kanata-{{ INSTANCE }}"
    # Alternative to the root kanata-blueturn.srv.pb: the BlueTurn pedal
    # runs a PRIVATE kanata build (build.src.pb; tcp_server+cmd, upstream
    # stable tag) and exposes the kanata TCP protocol on loopback, so the
    # Edge keyboard's spare F19/F20 (kanata-a-keyboard) can switch pedal
    # layers remotely instead of pedal semantics being baked into one
    # keymap. Installed link-only (shared profile: no enable/start) --
    # switching from the root blueturn example is deliberate: the two
    # instances fight over the same "iRig BlueTurn Keyboard" evdev node.
    #
    # Layer model (ChangeLayer targets pages/media):
    #   pages       first deflayer: startup default; LEFT tap pgup /
    #               RIGHT pgdn; target of ChangeLayer pages
    #   media       LEFT prev / RIGHT next (plain media keys)
    #   pedal-meta  held overlay from the LEFT tap-hold in pages:
    #               transparent (_) LEFT, RIGHT pp
    # Transparent fallback: kanata change_layer (1.12 src/kanata/mod.rs)
    # matches the name against deflayers and silently ignores unknown
    # ones, so a mis-sent name no-ops rather than crashing. The held
    # overlay falls through to the default layer; release pedals before
    # changing defaults. Media does not activate pedal-meta.
    #
    # Output naming: NO linux-output-device-name override anywhere in
    # these alternatives. kanata names its virtual output device
    # "kanata" and main's autodetect skips exactly that name
    # (src/oskbd/linux.rs is_input_device); a renamed output would be
    # re-grabbed and reprocessed by the running main instance.
    # Observability comes from the distinct unit name instead.
    #
    # Same kernel caveat as the root blueturn example: 7.1 hid-core
    # drops the pedal's 7-byte reports until 7.2/backport
    # cfc0d283d931 (design/blueturn/blueturn-linux-research.general.md).
    #
    # SystemD_SERVICE explicit so the unit is kanata-a-pedal.service
    # (NAME-derived default would be identical, but spelling it out
    # keeps the three alternatives grep-able and the shared
    # SYSTEMD_ALIAS: false story obvious: -a-pedal must never alias
    # kanata.service and fight the packaged unit).
    SYSTEMD_SERVICE: kanata-a-pedal
    # Private tcp_server+cmd binary from build.src.pb. Real file (the
    # build bin cp's it), never a symlink through the /home archive:
    # the unit runs under ProtectHome=true as _kanata.
    KANATA_BIN: /usr/local/src/kanata-a-build/bin/kanata
    KANATA_A_TCP_ADDR: 127.0.0.1:16666
    # Service overrides, combined onto the shared KANATA_SERVICE_BASE
    # baseline (no repeated sandbox):
    # - ExecStart gains --port: the tcp_server feature listener. Bound
    #   to loopback by address; the sandbox also pins it (below).
    # - PrivateNetwork 'no': the TCP server needs host loopback. Kept
    #   as the STRING 'no' because the unit template silently drops
    #   bare `false` values, and an explicit PrivateNetwork=no beats
    #   relying on the systemd default.
    # - AF_INET joins AF_UNIX for the listener socket; PrivateUsers
    #   stays ON (user namespaces do not affect AF_INET loopback).
    # - IPAddressAllow localhost + the base's IPAddressDeny any is
    #   systemd's canonical localhost-only shape.
    # - ExecStartPre is the prerequisite gate: the config must parse
    #   with THIS binary, and the binary must exist -- a fresh host
    #   that skipped build.src.pb fails here, in the journal, before
    #   ExecStart can grab a device (Restart=on-failure still retries).
    #   --check parses and exits without
    #   touching /dev/input (upstream main.rs args.check path).
    TCP_SERVICE_CONFIG: "{{ KANATA_SERVICE_BASE | combine({
      'ExecStart': KANATA_BIN ~ ' --cfg ' ~ ETC ~ '/kanata.kbd --port ' ~ KANATA_A_TCP_ADDR,
      'PrivateNetwork': 'no',
      'RestrictAddressFamilies': ['AF_UNIX', 'AF_INET'],
      'IPAddressAllow': ['localhost'],
      'ExecStartPre': KANATA_BIN ~ ' --check --cfg ' ~ ETC ~ '/kanata.kbd',
    }) }}"
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            process-unmapped-keys yes
            ;; whole instance scoped to the pedal: exact-name match (no
            ;; regex); name from kanata's own "registering" log line.
            ;; Virtual output keeps the DEFAULT "kanata" name (see
            ;; playbook header) -- main's autodetect skips exactly it.
            linux-dev-names-include (
              "iRig BlueTurn Keyboard"
            )
            ;; the pedal sleeps when idle: at boot (or after long idle)
            ;; zero matching devices exist -- keep running and let the
            ;; /dev/input watcher pick it up on reconnect
            linux-continue-if-no-devs-found yes
          )

          ;; TCP-selected layers. `pages` (first deflayer) is the startup
          ;; default: a pedal that just booted pages, no client required.
          ;; kanata-a-keyboard's
          ;; blueturn-switch sends {"ChangeLayer":{"new":"pages"|"media"}}.
          (defsrc
            pgup pgdn
          )

          (deflayer pages
            (tap-hold 180 180 pgup (layer-while-held pedal-meta))
            pgdn
          )

          (deflayer media
            prev
            next
          )

          ;; held overlay activated by LEFT hold in pages only:
          ;; LEFT stays transparent (_) -- the press falls through to
          ;; the default layer's action -- while RIGHT becomes pp.
          (deflayer pedal-meta
            _
            pp
          )
  tasks:
    - include_defaults:
        file: vars/common.yaml
    - set_fact:
        SYSTEMD_SERVICES: "{{ TCP_SERVICE_CONFIG }}"
    - import_tasks: ../../../tasks/compfuzor.includes
