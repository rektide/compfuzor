---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    INSTANCE: edge-one-shot
    SYSTEMD_SERVICE: kanata-edge-one-shot
    # Manual SmartSet prerequisite in the active layouts/layoutN.txt:
    # [hk5]>[f21]
    # [hk6]>[f22]
    # fn [hk5]>[f21]
    # fn [hk6]>[f22]
    # Remaps must emit real press/release, NOT modifier-tap macros.
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            ;; Ordinary keys outside defsrc must consume armed one-shots.
            process-unmapped-keys yes
            linux-dev-names-include ("Kinesis Freestyle Edge RGB Keyboard")
            linux-continue-if-no-devs-found yes
          )
          ;; $name substitutes data; @name refers to a parsed action.
          (defvar caps-timeout 100 modifier-timeout 1000)
          (defalias
            cap (tap-hold $caps-timeout $caps-timeout esc lctl)
            alt-next (one-shot $modifier-timeout lalt)
            win-next (one-shot $modifier-timeout lmet)
          )
          (defsrc caps f21 f22)
          ;; Tap: next-key modifier, expiring after 1000 ms. Hold: normal
          ;; held modifier. Unlike (macro lalt), this supports chords.
          (deflayer base @cap @alt-next @win-next)
  tasks:
    - import_tasks: ../../../tasks/compfuzor.includes
