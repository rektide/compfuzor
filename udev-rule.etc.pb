---
- hosts: all
  vars:
    TYPE: udev-rule
    INSTANCE: main
    ETC_FILES:
      - dest: '80-{{NAME}}.rules'
        src: rules
        link: "/etc/udev/rules.d/80-{{NAME}}.rules"
    # TODO: ENV/ENVS
    action: change
    subsystem: usb
    devices:
      - manufacturer: Razer
        set:
          "power/control": "on"
      - manufacturer: Kinesis
        set:
          "power/control": "on"
      # https://github.com/raspberrypi/rpicam-apps/issues/218
      #- action: False
      #  subsystem: dma_heap
      #  group: video
      #  mode: "0660"
  tasks:
    - import_tasks: tasks/compfuzor.includes
