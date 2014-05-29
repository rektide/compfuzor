---
- hosts: all
  vars:
    TYPE: qpaeq
    INSTANCE: main
    REPO: git://gitorious.org/pulseaudio-equalizer/pulseaudio-equalizer.git 
    PKGS:
    - libsndfile1-dev
    - libspeexdsp-dev
    - fftw-dev
    - libdbus-1-dev
    - libgconf2-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: chdir="{{DIR}}" ./autogen.sh
  - shell: chdir="{{DIR}}" ./configure --prefix={{OPT}} --with-system-user=pulse --with-system-group=pulse --with-access-group=pulse-access
  - shell: chdir="{{DIR}}" make
  - shell: chdir="{{DIR}}" make install
    sudo: True
