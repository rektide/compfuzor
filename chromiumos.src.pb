---
# primarily for sommelier for now but maybe more latter. all credit to two works:
# - https://alyssa.is/using-virtio-wl/
# - https://github.com/skycocker/chromebrew/blob/master/packages/sommelier.rb
- hosts: all
  vars:
    TYPE: chromiumos-platform
    INSTANCE: git
    REPO: https://chromium.googlesource.com/chromiumos/platform2
    GET_URLS:
      virtwl.h.base64: "https://chromium.googlesource.com/chromiumos/third_party/kernel/+/5d641a7b7b64664230d2fd2aa1e74dd792b8b7bf/include/uapi/linux/virtwl.h?format=TEXT"
    ENV:
      CFLAGS: "-fuse-ld=ldd"
      CXXFLAGS: "-fuse-ld=ldd"
      #DISPLAY=:0
      #GDK_BACKEND=x11
      GDK_BACKEND=wayland
      CLUTTER_BACKEND=wayland
      #SCALE=0.5
      #SOMMELIER_ACCELERATORS=\"Super_L,<Alt>bracketleft,<Alt>bracketright\"
      WAYLAND_DISPLAY=wayland-1
      #XDG_RUNTIME_DIR=/var/run/chrome
      #UNAME_ARCH=$(uname -m)
    BINS:
    - name: build_sommelier.sh
      basedir: true
      exec: |
        base64 -d virtwl.h.base64 > virtwl.h
        cd vm_tools/sommelier
        sed -i 's/sizeof(addr.sun_path))/sizeof(addr.sun_path) - 1)/' sommelier.cc

        system "meson #{CREW_MESON_OPTIONS} -Dxwayland_path=#{CREW_PREFIX}/bin/Xwayland \
          -Dxwayland_gl_driver_path=/usr/#{ARCH_LIB}/dri -Ddefault_library=both \
          -Dxwayland_shm_driver=noop -Dshm_driver=noop -Dvirtwl_device=/dev/null \
          -Dpeer_cmd_prefix=\"#{CREW_PREFIX}#{PEER_CMD_PREFIX}\" build"
        system "meson configure build"
        system "ninja -C build"
  tasks:
  - include: tasks/compfuzor.includes type=src
