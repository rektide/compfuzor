---
- hosts: all
  vars:
    TYPE: rsdk
    INSTANCE: git
    REPO: https://github.com/RadxaOS-SDK/rsdk
    PKGS:
      - lintian
      - dh-exec
      - shellcheck
      - bash-completion
      - bdebstrap
      - mmdebstrap
      - debian-ports-archive-keyring
      - whiptail
      - libnewt-dev
      - jsonnet
      - arch-test
      - guestfish
      - libguestfs-tools
      - gir1.2-guestfs-1.0
      - libguestfs-dev
      # swag that mmdebstrap recommends
      - uidmap
      - apt-utils
      - e2fsprogs
      - fakechroot
      - genext2fs
      - lz4
      - qemu-user-static
      - qemu-user
      - zstd
    BINS:
      - name: build.sh
        exec: |
          echo building rtui dependency
          cd externals/librtui
          dpkg-buildpackage -us -uc
          cd ../..
          ln -s externals/librtui_0.1.0_all.deb .
          echo
          echo building rsdk
          dpkg-buildpackage -us -uc
          ln -s ../rsdk_0.1.0_all.deb .
      - name: build-fix-rtui.sh
        exec: |
          # nothing about radxa is any fun or any good and this just is such final salt on their
          # shitty cobbled together utterly undocumented "good luck" garbage smdh
          ln -s /usr/lib/libtrui /usr/lib/librtui
      - name: build-03w.sh
        exec: |
          rsdk build --sdboot --debug radxa-zero3
  tasks:
    - import_tasks: tasks/compfuzor.includes
