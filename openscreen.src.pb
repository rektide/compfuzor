---
- hosts: all
  vars:
    TYPE: openscreen
    INSTANCE: git
    depot_tools: depot-tools-git
    repo: https://chromium.googlesource.com/openscreen
    PKGS:
    - ninja-build
    - generate-ninja
    - clang-format
    - libstdc++-15-dev
    - libsdl2-compat-dev
    - libavcodec-dev
    - libavformat-dev
    - libavutil-dev
    - libswresample-dev
    - libopus-dev
    - libvpx-dev
    - libaom-dev
    - libwebkit2gtk-4.1-dev
    ENV:
      OS_DEPOT_TOOLS: "{{depot_tools|defaultDir(SRCS_DIR)}}/"
      OS_REPO: "{{repo}}"
    BINS:
    - name: checkout.sh
      run: True
      exec: |
        ${OS_DEPOT_TOOLS}gclient config ${OS_REPO}
        ${OS_DEPOT_TOOLS}gclient sync
    - name: build.sh
      basedir: openscreen
      exec: |
        # do interactively?
        #gn args out/Default
        #mkdir -p out/debug
        # Creates the build directory and necessary ninja files
        #gn gen out/debug
        gn gen --args="have_ffmpeg=true have_libsdl2=true have_libopus=true have_libvpx=true have_libaom=true" out/release
        # Builds the executable with ninja
        ninja -C out/release osp_demo
  tasks:
  - import_tasks: tasks/compfuzor.includes
