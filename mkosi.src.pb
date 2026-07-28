---
- hosts: all
  vars:
    REPO: https://github.com/systemd/mkosi
    ENV:
      scratchsize: "{{scratchsize|default()}}"
      INSTANCE: git
      hostname: "{{hostname|default('debos')}}"
      user: "{{user|default(ansible_user_id)}}"
      password: "{{password|default('CHANGE_OR_ELSE')}}"
    MKOSI_PKGS: []
    MKOSI_PKGSETS:
      - BASE
      # TODO: eventually support "BASE_{{ARCH}}" parametric pkgsets so the
      # amd64/arm64-specific sets resolve automatically from ARCH.
      - BASE_amd64
      # - WORKSTATION
      # - VIRTUALIZATION
      # - WORKSTATION_X
      # - OPENCL
      # - XPRA
      # - DEVEL
      # - DEBDEV
      # - AUDIO
      # - AUDIO_X
      # - BT
      # - BT_X
      # - RYGEL
      # - RYGEL_X
      # - USERSPACE
      # - JACK
      # - JACK_X
      # - MEDIA
      # - VAAPI
      # - VAAPI_amd64
      # - WORKSTATION_WAYLAND
      # - MEDIA_X
      # - POSTGRES
      # - CONTAINER
      # - BONUS
      # - WORDS
    ETC_FILES:
      - name: pkgs.txt
        content: "{{ lookup('template', '../../files/_pkgs') }}"
    BINS:
      - name: build-debian.sh
        exec: |
          # btrfs rootdir recommended!

          commaSep(){
            paste -sd, "$1"
          }
          mkosi \
            --distribution debian \
            --release trixie \
            --format disk \
            --checksum \
            --root-password "$PASSWORD" \
            --include mkosi-vm \
            --package "$(commaSep etc/pkgs.txt)" \
            --repository-key-fetch yes \
            --output image.raw \
            "$@"
      - name: run-nspawn.sh
        exec: |
          systemd-nspawn --boot --image image.raw
    ARCH_PKGS:
      - debootstrap
      - debian-archive-keyring
      - apt
  tasks:
    - import_tasks: tasks/compfuzor.includes
