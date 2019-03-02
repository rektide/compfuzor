---
- hosts: all
  vars:
    TYPE: sony-pm-alt
    INSTANCE: git
    REPO: https://github.com/falk0069/sony-pm-alt
    PKGS:
    - libusb-1.0-0-dev
    - gssdp-tools
    BINS:
    - name: build.sh
      basedir: "{{SRC}}"
      run: True
      content: |
        gcc sony-guid-setter.c -lusb-1.0 -o sony-guid-setter
    - name: find-camera.sh
        gssdp-discover --timeout=5
    - link: "{{SRC}}/sony-guid-setter"
      delay: postRun
  tasks:
  - include: tasks/compfuzor.includes type=opt
