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
      COLORD: "{{SRCS_DIR}}/colord-{{INSTANCE}}"
    BINS:
    - name: build.sh
      content: |
        [ -f $COLORD/env.export ] && source $COLORD/env.export
        ./autogen.sh
        make
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
