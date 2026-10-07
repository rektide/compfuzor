---
# Optional producer + inert system artifacts. Render does not install copies,
# units, producer membership, services or compositor configuration.
- hosts: all
  vars:
    TYPE: kanata-dial
    INSTANCE: main
    PREFIX_DIR: "{{ ansible_env.XDG_DATA_HOME | default(ansible_env.HOME ~ '/.local/share', true) }}/compfuzor/etc"
    ETC: "{{DIR}}"
    KEYBINDING_PRODUCER: kanata-dial
    KEYBINDING_ORDER: 110
    ACTION_AUDIENCES: {default: user, available: [user, system]}
    # User-selected precision amount; base media-keys .03/.01 unchanged.
    KANATA_DIAL_PRECISION_STEP: "0.003"
    KANATA_DIAL_SYSTEM_ROOT: /etc/opt/kanata-dial-main
    KANATA_DIAL_NODE: /usr/bin/node
    KANATA_DIAL_KEYBOARD_PORT: 5828
    KANATA_DIAL_PORT: 5829
    SYSTEMD_ALIAS: false
    SYSTEMD_ENABLE: false
    SYSTEMD_START: false
    SYSTEMD_INSTALL_STRATEGY: copy
    SYSTEMD_ROOTS: [dial_network, dial_input, dial_relay, dial_reset]
    dial_network:
      SYSTEMD_SERVICE: kanata-dial-network
      SYSTEMD_ALIAS: false
      SYSTEMD_UNITS:
        Description: Stable private loopback namespace for Kanata dial control
      SYSTEMD_SERVICES:
        ExecStart: /usr/bin/sleep infinity
        Restart: "no"
        DynamicUser: true
        PrivateNetwork: true
        PrivateTmp: "false"
        PrivateDevices: true
        DevicePolicy: closed
        NoNewPrivileges: true
        CapabilityBoundingSet: ""
        ProtectSystem: strict
        ProtectHome: true
        ProtectKernelTunables: true
        ProtectKernelModules: true
        ProtectKernelLogs: true
        ProtectControlGroups: true
        RestrictNamespaces: true
        RestrictAddressFamilies: AF_UNIX
        IPAddressDeny: any
        MemoryDenyWriteExecute: true
        UMask: "0077"
    dial_input:
      SYSTEMD_SERVICE: kanata-dial
      SYSTEMD_ALIAS: false
      SYSTEMD_UNITS:
        Description: Scoped Surface Dial Kanata remapper
        Requires: kanata.service kanata-dial-network.service
        BindsTo: kanata-dial-network.service
        Wants: modprobe@uinput.service
        After: kanata.service kanata-dial-network.service modprobe@uinput.service
        JoinsNamespaceOf: kanata-dial-network.service
      SYSTEMD_SERVICES:
        Type: simple
        User: _kanata
        Group: _kanata
        SupplementaryGroups: input
        # Fail closed if optional main-owner integration was not installed.
        ExecStartPre:
          - /usr/bin/test -d /run/kanata-dial-publisher
          - /usr/bin/grep -Fx ';; compfuzor kanata dial publisher enabled' /etc/kanata/config.kbd
        ExecStart: "/usr/local/bin/kanata --cfg {{KANATA_DIAL_SYSTEM_ROOT}}/dial.kbd --port 127.0.0.1:{{KANATA_DIAL_PORT}}"
        Restart: "no"
        CapabilityBoundingSet: ""
        DeviceAllow: [/dev/uinput rw, char-input, /dev/stdin]
        DevicePolicy: strict
        PrivateDevices: true
        BindPaths: /dev/uinput
        BindReadOnlyPaths: [/dev/stdin, /dev/input/, /etc/kanata/, "{{KANATA_DIAL_SYSTEM_ROOT}}"]
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
        RestrictAddressFamilies: [AF_UNIX, AF_INET]
        RestrictNamespaces: true
        SystemCallArchitectures: native
        SystemCallErrorNumber: EPERM
        SystemCallFilter: ["@system-service", "~@privileged", "~@resources"]
        RemoveIPC: true
        IPAddressDeny: any
        IPAddressAllow: 127.0.0.1/32
        RestrictSUIDSGID: true
        RestrictRealtime: true
        MemoryDenyWriteExecute: true
        UMask: "0077"
    dial_relay:
      SYSTEMD_SERVICE: kanata-dial-relay
      SYSTEMD_ALIAS: false
      SYSTEMD_UNITS:
        Description: Keyboard layer to dial precision TCP relay
        Requires: kanata-dial.service kanata-dial-network.service
        BindsTo: kanata-dial-network.service
        After: kanata-dial.service kanata-dial-network.service
        JoinsNamespaceOf: kanata-dial-network.service
      SYSTEMD_SERVICES:
        Type: simple
        DynamicUser: true
        ExecStart: "{{KANATA_DIAL_NODE}} {{KANATA_DIAL_SYSTEM_ROOT}}/cli.ts"
        ExecStopPost: "{{KANATA_DIAL_NODE}} {{KANATA_DIAL_SYSTEM_ROOT}}/cli.ts --reset"
        Environment:
          - "KANATA_KEYBOARD_PORT={{KANATA_DIAL_KEYBOARD_PORT}}"
          - "KANATA_DIAL_PORT={{KANATA_DIAL_PORT}}"
          - KANATA_PRECISION_LAYER=dial-precision
          - KANATA_DIAL_FALLBACK_LAYER=base
        Restart: on-failure
        RestartSec: 1
        TimeoutStopSec: 15
        PrivateNetwork: true
        PrivateTmp: true
        PrivateDevices: true
        DevicePolicy: closed
        NoNewPrivileges: true
        CapabilityBoundingSet: ""
        ProtectSystem: strict
        ProtectHome: true
        ProtectKernelTunables: true
        ProtectKernelModules: true
        ProtectKernelLogs: true
        ProtectControlGroups: true
        RestrictNamespaces: true
        RestrictAddressFamilies: [AF_UNIX, AF_INET]
        IPAddressDeny: any
        IPAddressAllow: 127.0.0.1/32
        # Native Node TS stripping needs Amaro WebAssembly. Input units keep MDWE.
        MemoryDenyWriteExecute: "false"
        UMask: "0077"
    dial_reset:
      SYSTEMD_SERVICE: kanata-dial-reset
      SYSTEMD_ALIAS: false
      SYSTEMD_UNITS:
        Description: Observe legacy fallback after dial precision reset
        Requires: kanata-dial-network.service
        BindsTo: kanata-dial-network.service
        After: kanata-dial.service kanata-dial-network.service
        JoinsNamespaceOf: kanata-dial-network.service
      SYSTEMD_SERVICES: >-
        {{ dial_relay.SYSTEMD_SERVICES | combine({
          'Type': 'oneshot',
          'ExecStart': KANATA_DIAL_NODE ~ ' ' ~ KANATA_DIAL_SYSTEM_ROOT ~ '/cli.ts --reset',
          'ExecStopPost': false, 'Restart': 'no', 'TimeoutStartSec': 10
        }) }}
    LINKS:
      - {src: "{{ETC}}/kanata-dial/dial.kbd", dest: "{{KANATA_DIAL_SYSTEM_ROOT}}/dial.kbd", scope: system, policy: replace, strategies: {available: [copy], default: copy}}
      - {src: "{{ETC}}/kanata-dial/protocol.ts", dest: "{{KANATA_DIAL_SYSTEM_ROOT}}/protocol.ts", scope: system, policy: replace, strategies: {available: [copy], default: copy}}
      - {src: "{{ETC}}/kanata-dial/relay.ts", dest: "{{KANATA_DIAL_SYSTEM_ROOT}}/relay.ts", scope: system, policy: replace, strategies: {available: [copy], default: copy}}
      - {src: "{{ETC}}/kanata-dial/cli.ts", dest: "{{KANATA_DIAL_SYSTEM_ROOT}}/cli.ts", scope: system, policy: replace, strategies: {available: [copy], default: copy}}
    BINS:
      - name: install-dial-runtime-dirs.sh
        action: install
        scope: system
        phase: main
        run: false
        content: |
          sudo -n /usr/bin/install -d -m 0755 {{KANATA_DIAL_SYSTEM_ROOT | quote}}
      - name: apply-dial-enhancement.sh
        action: apply
        scope: user
        run: false
        content: |
          exec {{KANATA_DIAL_NODE | quote}} "$ETC/kanata-dial/toggle.ts" "$@"
    KEYBINDING_ACTIONS:
      kanata-dial-volume-up-precision:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "{{KANATA_DIAL_PRECISION_STEP}}+", "-l", "1.0"]
      kanata-dial-volume-down-precision:
        exec: [wpctl, set-volume, "@DEFAULT_AUDIO_SINK@", "{{KANATA_DIAL_PRECISION_STEP}}-"]
    KEYBINDINGS:
      kanata-dial-volume-up-precision:
        action: kanata-dial-volume-up-precision
        keys: [F23]
        add-keys: [Shift+F23]
        title: Dial volume up (extra precision)
        niri:
          options: {allow-when-locked: true}
      kanata-dial-volume-down-precision:
        action: kanata-dial-volume-down-precision
        keys: [F24]
        add-keys: [Shift+F24]
        title: Dial volume down (extra precision)
        niri:
          options: {allow-when-locked: true}
    ETC_FILES:
      - name: kanata-dial/dial.kbd
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/dial.kbd') }}"
      - name: kanata-dial/keyboard-signal.example.kbd
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/keyboard-signal.example.kbd') }}"
      - name: kanata-dial/protocol.ts
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/protocol.ts') }}"
      - name: kanata-dial/relay.ts
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/relay.ts') }}"
      - name: kanata-dial/cli.ts
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/cli.ts') }}"
      - name: kanata-dial/toggle.ts
        mode: "0644"
        content: "{{ lookup('file', 'files/kanata-dial/toggle.ts') }}"
    README: |
      # Optional Kanata dial media contribution

      Generated material is inert. `install-user.mjs` registers producer bindings
      using the existing receiver selection/registry mechanism. It does NOT start
      input services. `install-system.mjs` explicitly copies four runtime assets
      to {{KANATA_DIAL_SYSTEM_ROOT}} and four unit files to the system manager,
      with daemon-reload but no enable/start. No runtime service points into HOME.

      Keep media-keys enabled. Group `kanata-dial` (order 110) adds plain and
      Shift F23/F24 extra-fine actions; selected step is
      {{KANATA_DIAL_PRECISION_STEP}}, configurable at render time.
      Base dial output remains Shift+Volume and existing media fine steps.

      Main ownership remains `kanata.srv.pb`: opt into `KANATA_DIAL_ENABLED=true`
      there, and explicitly preserve the desired `KANATA_DEV_NAMES_EXCLUDE` list.
      The default is unchanged/off. A live BlueTurn-only topology is NOT silently
      replaced with the authored Kinesis exclusion. Config-preserving renders
      retain existing bytes; the dial cannot start without both main's enabled
      config marker and current-invocation RuntimeDirectory. Main must therefore
      be deliberately installed/restarted before the first dial activation.

      Whole-enhancement toggle after explicit system installation/main handoff:
      `bin/apply-user.mjs on|off --niri-profile /absolute/profile.json` and/or
      `--umbriel-profile /absolute/profile.json --apply-command /absolute/hook`.
      `--context` defaults to user; profiles are explicit, not discovered here.
      The hook is operator-selected configuration application, with no automatic
      reload default. It receives on|off plus --TARGET-profile/--TARGET-context
      for each selected receiver. On ON it must also confirm both precision
      directions, plain + Shift, are actually active: group enable preserves
      disabled individual slots and edited native placements. Successful CONFIG
      publication alone does not prove live compositor readiness.
      Use this toggle rather than directly disabling membership
      while the relay could still emit precision F keys.

      ON: stop/reset relay, start/check dial base, install/enable all selected
      receivers through existing membership APIs, run apply hook, then start relay.
      A receiver/hook failure does not start relay; partial membership is possible.
      OFF: disable --now relay (preventing automatic/boot restart), start the namespace-local
      reset one-shot and require observed base, then disable membership and apply.
      Dial/anchor remain running in legacy fallback. Failed reset stops dial as
      fail-safe and RETAINS F bindings; retry OFF after repairing the target.
      Membership and systemd operations are NOT one CONFIG transaction.

      The user toggle deliberately invokes `sudo -n /usr/bin/systemctl`; it is
      not a privilege broker or authorization bypass. It needs operator-approved
      noninteractive authority for the selected unit operations. Only one toggle
      and one precision controller may run at a time. No persistent boot enablement
      is inferred from membership; services installed here start only on explicit ON.

      Stable `kanata-dial-network.service` owns loopback namespace. Participants
      Requires/After/Bind to it and join it; its PrivateTmp=false does not share
      participant tmp namespaces. Anchor failure stops participants rather than
      silently restarting into a fragmented namespace. Re-run approved ON after
      repair; main/dial restarts do not replace the anchor namespace. Relay failure
      uses StopPost reset plus reset-on-reconnect; SIGKILL is not an automatic lease.

      Relay environment: KANATA_KEYBOARD_PORT, KANATA_DIAL_PORT (required),
      optional *_HOST (loopback only), KANATA_PRECISION_LAYER=dial-precision,
      KANATA_DIAL_VIRTUAL_KEY=precision-hold, KANATA_DIAL_FALLBACK_LAYER=base.
      {{KANATA_DIAL_NODE}} must support native TS stripping (system Node tested).
      Relay/reset alone omit executable-memory denial because Node TS needs
      WebAssembly; input units retain MemoryDenyWriteExecute=true. Do not use
      --jitless or --no-expose-wasm for native TS on the verified Node version.
      `node kanata-dial/cli.ts` runs relay; `--reset` is target-only stop helper.
      Do not run these against live input servers until deployment is authorized.
  tasks:
    - import_tasks: tasks/compfuzor.includes
