---
- hosts: all
  vars:
    TYPE: armbian-build
    INSTANCE: git
    REPO: https://github.com/armbian/build
    DIRS:
      - toolchain
      - rootfs
    BINS:
      - name: build.sh
        exec: |
          # https://docs.armbian.com/Developer-Guide_Build-Switches/
          ./compile.sh \
            BOARD=radxa-zero3 \
            BRANCH=edge \
            RELEASE=sid \
            BUILD_MINIMAL=no \
            BUILD_DESKTOP=no \
            INSTALL_HEADERS=yes \
            NETWORKING_STACK=systemd-networkd \
            DOCKER_ARMBIAN_BASE_IMAGE=ubuntu:noble \
            ROOTFS_TYPE=btrfs \
            BTRFS_COMPRESSION=zstd \
            ENABLE_EXTENSIONS=mesa-vpu,v4l2loopback-dkms,radxa-aic8800 \
            CONSOLE_AUTOLOGIN=no \
            PROGRESS_LOG_TO_FILE=yes \
            USE_MAINLINE_GOOGLE_MIRROR=yes \
            ARMBIAN_CACHE_ROOTFS_PATH=$(pwd)/rootfs \
            ARMBIAN_CACHE_TOOLCHAIN_PATH=$(pwd)/toolchain \
            BOOTSIZE=512 \
            KERNEL_GIT=full \
            EXPERT=yes
  tasks:
    - import_tasks: tasks/compfuzor.includes
    
