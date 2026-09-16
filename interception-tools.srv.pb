---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: main
    ARCH_PKGS:
      - interception-tools
      - interception-caps2esc
    INTERCEPTION_TOOLS: /usr/bin
    SYSTEMD_SERVICE: true
    SYSTEMD_UNITS:
      Wants: systemd-udev-settle.service
      After: systemd-udev-settle.service
    SYSTEMD_SERVICES:
      ExecStart: "{{INTERCEPTION_TOOLS}}/udevmon -c {{ETC}}/interception.yaml"
      CPUSchedulingPriority: 5
      CPUSchedulingPolicy: fifo
      Environment:
        - "PATH={{ INTERCEPTION_TOOLS }}:/usr/bin:/bin"
      Nice: -18
    SYSTEMD_INSTALLS:
      WantedBy: multi-user.target
    ETC_DIRS:
      - interception.yaml.d
    ETC_FILES:
      - name: interception.yaml.d/caps2esc.yaml
        content: |
          - JOB: "intercept -g $DEVNODE | caps2esc | uinput -d $DEVNODE"
            DEVICE:
              EVENTS:
                EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
              NAME: .*([Kk]eyboard|Freestyle).*
    CONFIGS:
      interception.yaml:
        processor: concat
  tasks:
    - import_tasks: tasks/compfuzor.includes
