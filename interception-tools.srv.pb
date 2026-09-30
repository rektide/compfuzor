---
- hosts: all
  vars:
    TYPE: interception-tools
    INSTANCE: main
    # Consolidated deployment 2026-09-30: interception-tools.src.pb (git
    # build into /opt + global links) retired -- Debian ships newer than
    # the 2020-built binaries that were shadowing /usr/bin via
    # /usr/local/bin symlinks. Packages + service + config compositor all
    # live here now. (The old srv playbook's ARCH_PKGS was a pacman-lane
    # bug on Debian -- it never installed anything.)
    PKGS:
      - interception-tools
      - interception-caps2esc
    SYSTEMD_UNITS:
      Description: interception-tools -- composable input device infrastructure (udevmon)
      Documentation: https://gitlab.com/interception/linux/tools
      Wants: systemd-udev-settle.service
      After: systemd-udev-settle.service
    SYSTEMD_SERVICES:
      Type: simple
      ExecStart: /usr/bin/udevmon -c {{ETC}}/interception.yaml
      # real-time input pipeline: beat the scheduler to the keypress
      CPUSchedulingPolicy: fifo
      CPUSchedulingPriority: 5
      Nice: -18
      Environment: "PATH=/usr/bin:/bin"
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
    # compositor: concat interception.yaml.d/*.yaml -> interception.yaml
    CONFIGS:
      interception.yaml:
        processor: concat
  tasks:
    - import_tasks: tasks/compfuzor.includes
