---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    INSTANCE: a-keyboard-hotkeys
    SYSTEMD_SERVICE: kanata-a-keyboard-hotkeys
    # No cmd feature needed here: compositor bindings own the TCP client.
    # Install the sibling helper outside /home and bind F19 -> pages,
    # F20 -> media, using that installed executable plus one argv.
    ETC_FILES:
      - name: blueturn-switch
        src: "{{ playbook_dir }}/scripts/blueturn-switch"
        raw: true
        mode: "0755"
      - name: kanata.kbd
        mode: "0644"
        content: |
          (defcfg
            process-unmapped-keys yes
            linux-dev-names-include ("Kinesis Freestyle Edge RGB Keyboard")
            linux-continue-if-no-devs-found yes
          )
          ;; SmartSet prerequisite: [hk3]>[f19] [hk4]>[f20]
          ;; and [hk5]>[f21] [hk6]>[f22]. Refresh and disconnect v-Drive.
          ;; F19/F20 are emitted, NOT consumed by cmd: compositor binds
          ;; invoke blueturn-switch pages/media outside this sandbox.
          ;; Keep default virtual output name "kanata": main skips it.
          (defsrc caps f19 f20 f21 f22)
          (deflayer base
            (tap-hold 100 100 esc lctl)
            f19 f20 lalt lmet
          )
  tasks:
    - set_fact:
        PKGS: [kanata, python3]
    - import_tasks: ../../../tasks/compfuzor.includes
