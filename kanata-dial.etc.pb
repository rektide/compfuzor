---
# Offline material + separately selectable media contribution. No units, live
# links, service starts or membership changes are performed by this playbook.
- hosts: all
  vars:
    TYPE: kanata-dial
    INSTANCE: main
    PREFIX_DIR: "{{ ansible_env.XDG_DATA_HOME | default(ansible_env.HOME ~ '/.local/share', true) }}/compfuzor/etc"
    ETC: "{{DIR}}"
    KEYBINDING_PRODUCER: kanata-dial
    KEYBINDING_ORDER: 110
    ACTION_AUDIENCES: {default: user}
    # Candidate amount: override explicitly; base media-keys .03/.01 unchanged.
    KANATA_DIAL_PRECISION_STEP: "0.003"
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
        mode: "0755"
        content: "{{ lookup('file', 'files/kanata-dial/cli.ts') }}"
    README: |
      # Optional Kanata dial media contribution

      Generated material is inert. Installing the generated user producer
      registers F23/F24 bindings; it does NOT start an input instance or relay.
      Service/namespace/main configuration integration remains separately gated.

      Keep media-keys enabled. Group `kanata-dial` (order 110) adds plain and
      Shift F23/F24 extra-fine actions; candidate step is
      {{KANATA_DIAL_PRECISION_STEP}}, configurable at render time.
      Base dial output remains Shift+Volume and existing media fine steps.

      Enable ordering: validate/install or enable this group in each intended
      consumer, explicitly apply compositor configuration, then start relay.
      Disable ordering: stop relay; run `node kanata-dial/cli.ts --reset` in
      its namespace and require success (or stop dial instance); only then
      disable group and explicitly apply compositor configuration.
      Membership and systemd operations are NOT one CONFIG transaction.

      Relay environment: KANATA_KEYBOARD_PORT, KANATA_DIAL_PORT (required),
      optional *_HOST (loopback only), KANATA_PRECISION_LAYER=dial-precision,
      KANATA_DIAL_VIRTUAL_KEY=precision-hold. Node native TS stripping required.
      `node kanata-dial/cli.ts` runs relay; `--reset` is target-only stop helper.
      Do not run these against live input servers until deployment is authorized.
  tasks:
    - import_tasks: tasks/compfuzor.includes
