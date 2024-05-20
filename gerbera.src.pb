---
- hosts: all
  vars:
    TYPE: gerbera
    INSTANCE: git
    REPO: https://github.com/gerbera/gerbera
    PKGS:
      - uuid-dev
      - libpugixml-dev
      - libsqlite3-dev
      - zlib1g-dev
      - libfmt-dev
      - libspdlog-dev
      - duktape-dev
      - libmysqlclient-dev
      - libcurl4-openssl-dev
      - libtag-dev
      - libwavpack-dev
      - libmagic-dev
      - libmatroska-dev
      - libebml-dev
      - libavcodec-dev
      - libexif-dev
      - libexiv2-dev
      #- liblastfm5-dev # not the one
      - libffmpegthumbnailer-dev
    BINS:
      - name: build.sh
        basedir: True
        content: |
          mkdir -p build
          cd build
          # -DWITH_DEBUG=YES
          cmake .. -DWITH_NPUPNP=YES -DWITH_MYSQL=1 -DWITH_AVCODEC=1 -DWITH_EXIV2=1 -DWITH_FFMPEGTHUMBNAILER=1
          make -j4
      - name: install.sh
        basedir: build
        content: |
          sudo make install

  tasks:
    - include: tasks/compfuzor.includes type=src
  
