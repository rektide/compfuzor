---
- hosts: all
  vars_files:
    - ../shared/service.yaml
  vars:
    INSTANCE: a-keyboard
    ETC: "{{ ETCS_DIR }}/kanata-{{ INSTANCE }}"
    SYSTEMD_SERVICE: kanata-a-keyboard
    KANATA_BIN: /usr/local/src/kanata-a-build/bin/kanata
    PKGS: [kanata, python3]
    # cmd executes the helper directly with argv, not a shell. The client
    # needs the host loopback namespace, like the pedal TCP listener.
    TCP_SERVICE_CONFIG: "{{ KANATA_SERVICE_BASE | combine({
      'PrivateNetwork': 'no',
      'RestrictAddressFamilies': ['AF_UNIX', 'AF_INET'],
      'IPAddressAllow': 'localhost',
      'ExecStartPre': KANATA_BIN ~ ' --check --cfg ' ~ ETC ~ '/kanata.kbd'
    }) }}"
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
            danger-enable-cmd yes
          )
          ;; SmartSet prerequisite in the active RGB profile:
          ;; [hk3]>[f19] [hk4]>[f20] [hk5]>[f21] [hk6]>[f22]
          ;; Refresh, then disconnect v-Drive before testing.
          ;; Keep default virtual output name "kanata": main skips it.
          (defsrc caps f19 f20 f21 f22)
          (deflayer base
            (tap-hold 100 100 esc lctl)
            (cmd "{{ ETC }}/blueturn-switch" pages)
            (cmd "{{ ETC }}/blueturn-switch" media)
            lalt lmet
          )
  tasks:
    # vars_files outranks play vars; freeze the combined service as a fact
    # before Compfuzor renders it, rather than losing overrides silently.
    - include_defaults:
        file: vars/common.yaml
    - set_fact:
        SYSTEMD_SERVICES: "{{ TCP_SERVICE_CONFIG }}"
        PKGS: [kanata, python3]
    - import_tasks: ../../../tasks/compfuzor.includes
