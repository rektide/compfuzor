---
- hosts: all
  vars:
    TYPE: debos
    INSTANCE: main
    arch: amd64
    hostname: debos
    password: CHANGE_OR_ELSE
    scratchsize: 11g
    user: "{{ansible_user_id}}"

    ETC_FILES:
    - name: debos.yaml
    VAR_DIRS:
    - build
    VAR_FILES:
    - src: overlay
      dest: .
      raw: true
    LINKS:
    - src: /proc/self/mounts
      # symlinks don't work
      dest: "{{VARS_DIR}}/{{NAME}}/overlay/etc/mtab"
      force: true
    ENV:
      DEBOS_SCRATCHSIZE: "{{scratchsize}}"
    BINS:
    - name: build.sh
      basedir: "{{VAR}}/build"
      exec: |
        # debos can't resolve outside symlinks so we copy stuff into our working dir
        rsync -av {{VAR}}/overlay overlay
        cp {{ETC}}/debos.yaml debos.yaml
        debos -v --scratchsize=$DEBOS_SCRATCHSIZE debos.yaml
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
    - WORDS

    # PKGS:
    #- debos
    #- fakemachine
  tasks:
  - include: tasks/compfuzor.includes type=srv
