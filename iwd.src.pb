---
- hosts: all
  vars:
    TYPE: iwd
    INSTANCE: git
    REPO: https://git.kernel.org/pub/scm/network/wireless/iwd.git
    OPT_DIRS: True
    BINS:
    - name: build.sh
      run: True
      exec: |
        ./bootstrap
        ./configure --prefix="{{OPT}}" --disable-dependency-tracking
        make
        make install
    PKGS:
    - libreadline-dev
    - libell-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
