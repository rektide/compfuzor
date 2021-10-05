---
- hosts: all
  vars:
    TYPE: debos
    INSTANCE: main
    arch: amd64
    ETC_FILES:
    - name: debos.yaml
      content: "{{lookup('template', '../files/debos.yaml')}}"
    VAR_DIRS:
    - build
    BINS:
    - name: build.sh
      basedir: "{{VAR}}/build"
      exec: |
        # --disable-fakemachine
        debos {{ETC}}/debos.yaml
    pkgsets:
    - BASE
    - BASE_x86
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

    # PKGS:
    #- debos
    #- fakemachine
  tasks:
  - include: tasks/compfuzor.includes type=srv
