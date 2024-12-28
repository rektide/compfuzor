---
- hosts: all
  vars:
    TYPE: electricsheep
    INSTANCE: git
    REPO: https://github.com/scottdraves/electricsheep
    PKGS:
      libtool
      libgtk2.0-dev
      libgl1-mesa-dev
      libavcodec-dev
      libavformat-dev
      libswscale-dev
      liblua5.1-0-dev
      libcurl4-openssl-dev
      libxml2-dev
      libjpeg8-dev
      libgtop2-dev
      libboost-dev
      libboost-filesystem-dev
      libboost-thread-dev
      libtinyxml-dev
      freeglut3-dev
      glee-dev
      libwxgtk3.0-dev
    ENV: {}
    BINS:
      - name: build.sh
        exec: |
          ./autogen.sh
          #./configure --prefix=${DIR}
          ./configure
          make
          make install
  tasks:
    import_tasks: tasks/compfuzor.includes

          
          
