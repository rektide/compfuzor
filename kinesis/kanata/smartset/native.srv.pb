---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    INSTANCE: edge-native
    SYSTEMD_SERVICE: kanata-edge-native
    # Manual SmartSet prerequisite in the active layouts/layoutN.txt:
    # [hk5]>[lalt]
    # [hk6]>[lwin]
    # fn [hk5]>[lalt]
    # fn [hk6]>[lwin]
    # Remaps, NOT recorded macros; native Windows obeys hardware Game Mode.
    ETC_FILES:
      - name: kanata.kbd
        mode: "0644"
        content: |
          ;; Firmware owns hk5/hk6 modifiers; unmapped keys pass through.
          (defcfg
            process-unmapped-keys yes
            linux-dev-names-include ("Kinesis Freestyle Edge RGB Keyboard")
            linux-continue-if-no-devs-found yes
          )
          (defvar caps-timeout 100)
          (defalias cap (tap-hold $caps-timeout $caps-timeout esc lctl))
          (defsrc caps)
          (deflayer base @cap)
  tasks:
    - import_tasks: ../../../tasks/compfuzor.includes
