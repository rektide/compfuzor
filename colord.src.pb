---
- hosts: all
  vars:
    TYPE: colord
    INSTANCE: git
    REPO: https://github.com/hughsie/colord
    PKGS:
    - libdbus-1-dev
    - docbook
    - gettext
    - libglib2.0-devel
    - gobject-introspection
    #- gtk-doc
    - intltool
    - liblcms2-dev
    - libgudev-1.0-dev
    - libgusb-dev
    - libpolkit-gobject-1-dev
    - libsqlite3-dev
    - libsystemd-devel
    - vala-dbus-binding-tool
    - meson
    - argyll
    - libgirepository1.0-dev
    - dpkg-dev
    - gtk-doc-tools
    ENV:
      PKG_CONFIG_PATH: "{{DIR}}/opt/lib/x86_64-linux-gnu/pkgconfig"
    BINS:
    - name: build.sh
      content: |
        mkdir opt
        meson --prefix "{{DIR}}/opt" . build/
        cd build
        ninja
        ninja install # afils but gets far enough
  tasks:
  - include: tasks/compfuzor.includes type=src
  
