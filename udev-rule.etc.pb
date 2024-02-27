---
- hosts: all
  vars:
    TYPE: udev-rule
    INSTANCE: main
    ETC_FILES:
      - destTemplate: '80-{{NAME}}.rules'
        src: rules
    LINKS:
      - srcTemplate: "{{ETC}}/80-{{NAME}}.rules"
        destTemplate: "/etc/udev/rules.d/80-{{NAME}}.rules"
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
    - include: tasks/compfuzor.includes
