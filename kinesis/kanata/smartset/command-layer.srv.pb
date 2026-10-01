---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    INSTANCE: edge-command-layer
    SYSTEMD_SERVICE: kanata-edge-command-layer
    # Manual SmartSet prerequisite (and matching fn rows): see README.
    # hk1..8 emit F13..F16, F21..F24 respectively, as held remaps.
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            process-unmapped-keys yes
            linux-dev-names-include ("Kinesis Freestyle Edge RGB Keyboard")
            linux-continue-if-no-devs-found yes
          )
          (defvar caps-timeout 100)
          (defalias
            cap (tap-hold $caps-timeout $caps-timeout esc lctl)
            commands (layer-while-held commands)
            ;; Ordered taps, not held letters. Test in a disposable text
            ;; field without modifiers held; no save/close side effects.
            hello (macro h e l l o)
          )
          (defsrc caps f13 f14 f15 f16 f21 f22 f23 f24)
          ;; hk5/6 remain held Alt/Windows; hk7 holds the command overlay.
          ;; hk1..4/hk8 forward raw F keys outside the overlay.
          (deflayer base @cap f13 f14 f15 f16 lalt lmet @commands f24)
          ;; hk1..4: common copy/paste/undo/redo shortcuts (app-dependent).
          ;; `_` in a HELD overlay falls through to base, preserving caps,
          ;; hk5/6 modifiers and hk7's release-bound layer action.
          (deflayer commands _ C-c C-v C-z C-S-z _ _ _ @hello)
  tasks:
    - import_tasks: ../../../tasks/compfuzor.includes
