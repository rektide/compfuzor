---
- hosts: all
  vars:
    TYPE: mmdebstrap
    INSTANCE: main
    arch: amd64
    mmpkgset:
    - BASE
    - BASE_amd64
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
    - CONTAINER
    - BONUS
    mmpkgs: "{{lookup('template', '../files/mmdebstrap/_pkgs')}}"
    MMDEBSTRAP_COMPONENTS: "main,contrib,non-free"
    MMDEBSTRAP_SUITE: sid
    ENVS:
      MMDEBSTARP_COMPONENTS: true
      MMDEBSTRAP_SUITE: true
    ETC_FILES:
    - name: pkgs
      content: "{{mmpkgs}}"
    BINS:
    - name: build.sh
      exec: |
        mmdebstrap --format="directory" --components="${MMDEBSTRAP_COMPONENTS:-{{MMDEBSTRAP_COMPONENTS}}}" --include="$(sed -z 's/\n/,/g' etc/pkgs)" "${MMDEBSTRAP_SUITE:-{{MMDEBSTRAP_SUITE}}}" "{{VAR}}/build"
    VAR_FILES:
    - src: overlay
      dest: .
      raw: true
    VAR_DIRS:
    - build
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
