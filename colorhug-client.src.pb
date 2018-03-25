---
- hosts: all
  vars:
    TYPE: colorhug-client
    INSTANCE: git
    REPO: https://github.com/hughski/colorhug-client
    PKGS:
    - libusb-dev
    - libgusb-dev
    - yelp-tools
    - gobject-introspection
    - libgtk-3-dev
    - libcolord-dev
    - libcolord-gtk-dev
    - libsoup2.4-dev
    - libcolorhug-dev # inside colord repo blah
    - docbook
    ENVS:
      COLORHUG_LIBS: "-l{{SRCS_DIR}}/colord-{{INSTANCE}}/build/lib"
      COLORHUG_CFLAGS: "-I{{SRCS_DIR}}/colord-{{INSTANCE}}/lib/colorhug"
    BINS:
    - name: build.sh
      content: ./autogen.sh
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
