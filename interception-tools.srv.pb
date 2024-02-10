---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: main
    INTERCEPTION_TOOLS: /usr/bin
    SYSTEMD_WANTS: systemd-udev-settle.service
    SYSTEMD_AFTER: systemd-udev-settle.service
    SYSTEMD_EXEC: "{{INTERCEPTION_TOOLS}}/udevmon -c {{ETC}}/caps2esc.yaml"
    SYSTEMD_CPU_SCHEDULING_PRIORITY: 92
    SYSTEMD_WANTED_BY: multi-user.target
    SYSTEMD_ENVIRONMENT:
    - "PATH={{ INTERCEPTION_TOOLS }}:/usr/bin:/bin"
    SYSTEMD_NICE: -18
    ETC_FILES:
    - name: caps2esc.yaml
      content: |
        - JOB: "intercept -g $DEVNODE | caps2esc | uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
  tasks:
  - include: tasks/compfuzor.includes type=srv
