---
- hosts: all
  vars:
    TYPE: mmdebstrap
    INSTANCE: main
    arch: amd64
    mmpkgset:
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
    - PIPEWIRE
    - BT
    - BT_X
    - RYGEL
    - RYGEL_PREFERENCES
    - USERSPACE
    - JACK
    - JACK_X
    - MEDIA
    - VAAPI
    - VAAPI_amd64
    - WORKSTATION_WAYLAND
    - MEDIA_X
    - POSTGRES
    #mmpkgs: "{%set sep=joiner(',')%}{%for s in mmpkgset%} {{sep()}}{{(vars[s]|default(hostvars[inventory_hostname][s])|join(',')}}{%endfor%}"
    mmpkgs: "{% set sep=joiner(',) %}{{ sep() }}{{ sep() }}yas"
    #mmpkgs: "wut"
    BINS:
    - name: build.sh
      exec: |
        mmdebootstrap --format="directory" --components="main,contrib,non-free" --include="{{mmpkgs}}" sid {{VAR}}
    VARS_DIR: build
    PKGS:
    - mmdebstrap
    - arch-test
    - fakechroot
    - fakeroot
    - gpg
    - libdistro-info-perl
    - uidmap
    - apt-transport-https
    - apt-utils
    - binfmt-support
    - ca-cerficates
    - distro-info
    - distro-info-data
    - dpkg-dev
    - genext2fs
    - perl-doc
    - proot
    - qemu-user
    - qemu-user-static
    - squashfs-tools-ng
  tasks:
  - include: tasks/compfuzor.includes type=srv
