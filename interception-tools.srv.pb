---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: main
    INTERCEPTION_TOOLS: /usr/bin
    CONFIG_KEY: interception
    SYSTEMD_WANTS: systemd-udev-settle.service
    SYSTEMD_AFTER: systemd-udev-settle.service
    SYSTEMD_EXEC: "{{INTERCEPTION_TOOLS}}/udevmon -c {{ETC}}/interception.yaml"
    SYSTEMD_CPU_SCHEDULING_PRIORITY: 5
    SYSTEMD_CPU_SCHEDULING_POLICY: fifo
    SYSTEMD_WANTED_BY: multi-user.target
    SYSTEMD_ENVIRONMENT:
    - "PATH={{ INTERCEPTION_TOOLS }}:/usr/bin:/bin"
    - "CONFIG_KEY=interception"
    SYSTEMD_NICE: -18
    ETC_FILES:
    - name: interception/caps2esc.yaml
      content: |
        - JOB: "intercept -g $DEVNODE | caps2esc | uinput -d $DEVNODE"
          DEVICE:
            EVENTS:
              EV_KEY: [KEY_CAPSLOCK, KEY_ESC]
            NAME: .*([Kk]eyboard|Freestyle).*
  tasks:
    - import_tasks: tasks/compfuzor.includes
