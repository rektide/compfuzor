---
- hosts: all
  vars:
    # TYPE: kanata comes from ../shared/service.yaml (link-only, sandboxed,
    # ExecStart pointed at the staged {{ETC}}/kanata.kbd -- no /etc/kanata
    # links). This play adds only what is per-instance.
    INSTANCE: b-merged
    # Unique unit name: kanata-b-merged.service. Nothing aliases to the
    # packaged kanata.service (shared sets SYSTEMD_ALIAS: false), nothing
    # enables or starts it (SYSTEMD_ENABLE/START: false).
    SYSTEMD_SERVICE: kanata-b-merged
    # Option B: ONE kanata instance owns BOTH the Kinesis Freestyle Edge
    # RGB keyboard node and the iRig BlueTurn pedal node, so a keyboard
    # key can switch the layer the PEDAL types into -- a pure in-process
    # layer-switch, no TCP/cmd helper like option A
    # (../tcp-control/, see doc/kinesis/kanata.md).
    #
    # The cost is shared identity: kanata has no per-device keymaps on
    # Linux (device-history is macOS-only; linux-dev-names-include scopes
    # a whole instance), so both devices land in the same defsrc columns
    # and the same timing/history state:
    #
    #   COLUMN COLLISION  the Edge's physical PgUp/PgDn keys share the
    #     pgup/pgdn columns with the pedal's LEFT/RIGHT pedals. In pages
    #     mode a physical PgUp TAP pages back like the pedal, and HOLDING
    #     it >= pedal-hold opens pedal-meta exactly like the pedal. In
    #     media mode physical PgUp/PgDn become prev/next track. The pedal
    #     can also reach media mode's columns, of course. No fix without
    #     device-aware mapping (option A) or genuinely unused keycodes.
    #
    #   SHARED INPUT STATE  tap-hold timers, one-shot arming and kanata's
    #     input history are per-configuration, not per-device: a pedal
    #     press inside a keyboard tap-hold window influences its outcome
    #     and vice versa.
    #
    #   OBSERVABILITY  do not give this instance a custom
    #     linux-output-device-name: kanata's Linux input detection skips
    #     only the literal output name "kanata"
    #     (src/oskbd/linux.rs is_input_device), so a renamed output would
    #     be re-grabbed and reprocessed by the always-running main
    #     instance (kanata.srv.pb). Keep the default output name; tell
    #     instances apart by unit name and journal tags.
    #
    # Switching variants is deliberate: stop kanata-kinata,
    # kanata-blueturn and any option-A services before starting this one
    # (two consumers of one evdev node never run concurrently). Main
    # (kanata.srv.pb) already excludes both device names and stays up.
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          ;; B -- one layout, two devices, persistent pedal pages.
          ;;
          ;; SmartSet prerequisite (v-Drive, SmartSet+F8; edit the ACTIVE
          ;; profile's layouts/layoutN.txt -- kinefolk's job, never this
          ;; playbook; full walkthrough: doc/kinesis/kanata.md):
          ;;
          ;;   [hk3]>[f19]        [hk4]>[f20]
          ;;   [hk5]>[f21]        [hk6]>[f22]
          ;;
          ;; plus the same four assignments in the hardware fn rows so
          ;; holding the keyboard's Fn cannot change these keys'
          ;; identity:
          ;;
          ;;   fn [hk3]>[f19]     fn [hk4]>[f20]
          ;;   fn [hk5]>[f21]     fn [hk6]>[f22]
          ;;
          ;; Until programmed, hk3-hk6 emit nothing (factory-blank Game
          ;; Bank) and their kanata columns are simply never pressed.
          (defcfg
            process-unmapped-keys yes
            ;; BOTH devices in one instance: exact-name matches (no
            ;; regex), names as printed by kanata's own "registering"
            ;; log lines. The Edge's "Kinesis Freestyle Edge RGB Keyboard
            ;; Consumer Control" node is a different exact name and stays
            ;; with main -- multimedia passes through untouched there.
            linux-dev-names-include (
              "Kinesis Freestyle Edge RGB Keyboard"
              "iRig BlueTurn Keyboard"
            )
            ;; the pedal sleeps when idle and the Edge's event node
            ;; number churns across replugs (event1/event2 seen): stay
            ;; up and let the /dev/input watcher reacquire both
            linux-continue-if-no-devs-found yes
            ;; deliberately NO linux-output-device-name: default output
            ;; "kanata" is the one name the main instance's autodetect
            ;; skips; renaming would invite double-processing.
          )

          ;; defvar: named numbers, substituted at load time. Change the
          ;; feel in one place.
          (defvar
            tap-timeout 100  ;; caps tap/hold -- current instances' feel
            pedal-hold 180   ;; LEFT pedal tap/hold -- pedal instance's feel
          )

          ;; defalias: named actions, referenced as @name in layers.
          (defalias
            pages (layer-switch pages)
            media (layer-switch media)
            cap (tap-hold $tap-timeout $tap-timeout esc lctl)
            meta (layer-while-held pedal-meta)
          )

          ;; columns: keyboard (caps, SmartSet-programmed hk3-hk6 via
          ;; f19-f22) and pedal (pgup/pgdn) share one defsrc -- kanata
          ;; cannot tell the devices apart. Physical keyboard PgUp/PgDn
          ;; sit in the SAME columns as the pedals: see the collision
          ;; notes in this file's playbook header and the README.
          (defsrc
            caps f19 f20 f21 f22 pgup pgdn
          )

          ;; DEFAULT PAGE (typing): the current kanata.srv.pb caps remap
          ;; and the current kanata-blueturn pedal semantics, unchanged.
          ;; f19/f20 are PERSISTENT page selectors (layer-switch: sticks
          ;; until the other is chosen; affects subsequent presses only).
          (deflayer pages
            @cap
            @pages
            @media
            lalt
            lmet
            (tap-hold $pedal-hold $pedal-hold pgup @meta)
            pgdn
          )

          ;; MEDIA PAGE: pedals (and, unavoidably, the keyboard's physical
          ;; PgUp/PgDn -- same columns) become previous/next track.
          ;;
          ;; EVERY switched base layer repeats caps, both selectors and
          ;; both modifiers EXPLICITLY. Do not "simplify" these to `_`:
          ;; the layer stack under a switched base goes straight to defsrc
          ;; (delegate-to-first-layer is not enabled), so `_` here would
          ;; emit raw f19/f20/f21/f22 and raw caps -- silently losing the
          ;; Alt/Windows modifiers, the page selectors and this very
          ;; remap. Repetition is the price of switching within one
          ;; shared defsrc.
          (deflayer media
            @cap
            @pages
            @media
            lalt
            lmet
            prev
            next
          )

          ;; pedal-meta: momentary overlay, entered by HOLDING the LEFT
          ;; pedal (or the keyboard's physical PgUp -- same column) in the
          ;; pages base; reachable only from there (media maps its columns
          ;; directly to prev/next, no tap-hold).
          ;;
          ;; Here `_` is CORRECT and powerful: pedal-meta sits on the
          ;; temporary-layer stack ABOVE whichever base page is active, so
          ;; transparent entries fall through to that base -- selectors,
          ;; modifiers and caps keep working while the overlay is held,
          ;; and a re-tap of the LEFT column falls to the base's pgup
          ;; action. Only the RIGHT column changes meaning: play/pause,
          ;; exactly the current kanata-blueturn behavior.
          (deflayer pedal-meta
            _
            _
            _
            _
            _
            _
            pp
          )
  vars_files:
    - ../shared/service.yaml
  tasks:
    - import_tasks: ../../../tasks/compfuzor.includes
