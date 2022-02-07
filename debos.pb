---
- hosts: all
  vars:
    TYPE: debos
    INSTANCE: main
    arch: amd64
    ETC_FILES:
    - name: debos.yaml
      #content: "{{lookup('template', '../files/debos.yaml')}}"
    VAR_DIRS:
    - build
    VAR_FILES:
    - src: overlay
      dest: .
      raw: true
    LINKS:
    - src: /proc/self/mounts
      dest: "{{VAR}}/overlay/etc/mtab"
      force: true
    BINS:
    - name: build.sh
      basedir: "{{VAR}}/build"
      exec: |
        debos {{ETC}}/debos.yaml
    pkgs: []
    #- "kernel-image-{{arch}}"
    #- "kernel-headers-{{arch}}"
    pkgsets:
    - BASE
    - "BASE_{{arch}}"
    - WORKSTATION
    - VIRTUALIZATION
    - WORKSTATION_X
    - OPENCL
    - XPRA
    - DEVEL
    - DEBDEV
    - AUDIO
    - AUDIO_X
    - BT
    - BT_X
    - RYGEL
    - RYGEL_X
    - USERSPACE
    - JACK
    - JACK_X
    - MEDIA
    - VAAPI
    - VAAPI_amd64
    - WORKSTATION_WAYLAND
    - MEDIA_X
    - POSTGRES
    - BONUS

    # PKGS:
    #- debos
    #- fakemachine
  tasks:
  - include: tasks/compfuzor.includes type=srv
