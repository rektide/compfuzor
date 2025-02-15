---
- hosts: all
  vars:
    TYPE: armbian-build
    INSTANCE: git
    REPO: https://github.com/armbian/build
    BINS:
      - name: build.sh
        exec: |
          ./compile.sh \
            BOARD=radxa-zero3 \
            BRANCH=edge \
            RELEASE=sid \
            INSTALL_HEADERS=yes \
            NETWORKING_STACK=systemd-networkd \
            DOCKER_ARMBIAN_BASE_IMAGE=ubuntu:noble \
            ROOTFS_TYPE=btrfs \
            BTRFS_COMPRESSION=zstd \
            ENABLE_EXTENSIONS=mesa-vpu,v4l2loopback-dkms \
            CONSOLE_AUTOLOGIN=no \
            PROGRESS_LOG_TO_FILE=yes \
            USE_MAINLINE_GOOGLE_MIRROR=yes \
            BOOTSIZE=512 \
            EXPERT=yes
  tasks:
    - import_tasks: tasks/compfuzor.includes
    
