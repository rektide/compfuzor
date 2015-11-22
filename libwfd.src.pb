---
- hosts: all
  vars:
    TYPE: libwfd
    INSTANCE: git
    REPO: git://people.freedesktop.org/~dvdhrm/libwfd
    GIT_ACCEPT: True
    OPT_DIR: True
    BINS:
    - exec: "test -f ./configure || NOCONFIGURE=1 ./autogen.sh"
    - exec: "./configure --prefix {{OPT|default(DIR)}}"
    - exec: make
    - exec: make install
    PKGCONFIG: True
  tasks:
  - include: tasks/compfuzor.includes type=src 
