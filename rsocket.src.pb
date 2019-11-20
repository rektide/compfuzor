---
- hosts: all
  vars:
    TYPE: rsocket
    INSTANCE: git
    REPO: https://github.com/rsocket/rsocket-cpp
    OPT_DIR: True
    PKGS:
    - googletest
    - libgtest-dev
    - libgoogle-glog-dev
    - libgflags-dev
    - libgmock-dev
    BINS:
    - name: build.sh
      basedir: True
      content: |
        mkdir -p build yarpl/build
        cd build
        #pushd .
        #cd yarpl/build
        #echo '[building yarpl]'
        #cmake ../
        #make
        #make install DESTDIR="{{OPT}}"

        #popd
        #echo
        #echo '[building rsocket]' 
        cmake ../
        make
        make install DESTDIR="{{OPT}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
