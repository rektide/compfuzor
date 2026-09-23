---
- hosts: all
  vars:
    REPO: https://github.com/mhx/dwarfs
    CMAKE: True
    CMAKE_INSTALL: True
    # upstream installs its helper to <prefix>/sbin/mount.dwarfs, but
    # mount(8) only searches /sbin:/usr/sbin -- bridge it so Type=dwarfs
    # .mount units (rimworld.opt.pb) can dispatch.
    LINKS:
      - src: /usr/local/sbin/mount.dwarfs
        dest: /usr/sbin/mount.dwarfs
        scope: system
        policy: replace
    PKGS:
      - ronn
      - librange-v3-dev
      - libboost-chrono-dev
      - libboost-program-options-dev
      - libboost-context-dev
      - libboost-filesystem-dev
      - libboost-regex-dev
      - libdouble-conversion-dev
      - libgoogle-glog-dev
      - libfast-float-dev
      - libflac-dev
      - libutf8proc-dev
      - python3-mistletoe
  tasks:
    - import_tasks: tasks/compfuzor.includes
