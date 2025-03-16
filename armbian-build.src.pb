---
- hosts: all
  vars:
    TYPE: armbian-build
    INSTANCE: git
    REPO: https://github.com/armbian/build
    DIRS:
      - toolchain
      - rootfs
    ETC_FILES:
      - name: userpatches-compfuzor
        contents: |
          #PACKAGE_LIST_ADDITIONAL="$PACKAGE_LIST_ADDITIONAL tmux neovim pipewire pipewire-bin pipewire-v4l2 pipewire-doc pipewire-libcamera pipewire-audio-client-libraries git wireless-tools usbip btrfs-progs bluez bluez-firmware gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-libav gstreamer1.0-pipewire gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly gstreamer1.0-plugin-rtsp gstreamer1.0-plugin-vaapi"
          add_packages_to_rootfs tmux neovim tmux neovim pipewire pipewire-bin pipewire-v4l2 pipewire-doc pipewire-libcamera pipewire-audio-client-libraries git wireless-tools usbip btrfs-progs bluez bluez-firmware gstreamer1.0-alsa gstreamer1.0-gl gstreamer1.0-libav gstreamer1.0-pipewire gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly
          #gstreamer1.0-plugin-rtsp gstreamer1.0-plugin-vaapi
          #KERNELBRANCH="tag:v6.13.2"
    BINS:
      - name: build.sh
        exec: |
          # https://docs.armbian.com/Developer-Guide_Build-Switches/
          # CLEAN_LEVEL=make,debs,images,cache
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
            EXPERT=yes $*
  tasks:
    - import_tasks: tasks/compfuzor.includes
    
