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
    BINS:
    - name: build.sh
      content: |
        meson . build/
        cd build
        ninja
  tasks:
  - include: tasks/compfuzor.includes type=src
  
