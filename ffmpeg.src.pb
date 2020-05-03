---
- hosts: all
  vars:
    TYPE: ffmpeg
    INSTANCE: git
    REPO: git://source.ffmpeg.org/ffmpeg.git
    OPT_DIR: True
    BINS:
    - name: build.sh
      exec: |
        ./configure \
        	--prefix="/opt/{{NAME}}" \
        	--extra-libs="-lpthread -lm" \
        	--enable-gpl \
        	--enable-libaom \
        	--enable-libass \
        	--enable-libfdk-aac \
        	--enable-libfreetype \
        	--enable-libmp3lame \
        	--enable-libopus \
        	--enable-libvorbis \
        	--enable-libvpx \
        	--enable-libx264 \
        	--enable-libx265 \
        	--enable-nonfree
        	#--pkg-config-flags="--static" \
        	#--extra-cflags="-I$HOME/ffmpeg_build/include" \
        	#--extra-ldflags="-L$HOME/ffmpeg_build/lib" \
        	#--bindir="$HOME/bin" \
        make
        make install
    PKGS:
    - libaom-dev
    - libass-dev
    - libfdk-aac-dev
    - libfreetype6-dev
    - libmp3lame-dev
    - libnuma-dev
    - libopus-dev
    - libsdl2-dev
    - libtool
    - libva-dev
    - libvdpau-dev
    - libvorbis-dev
    - libvpx-dev
    - libxcb1-dev
    - libxcb-shm0-dev
    - libxcb-xfixes0-dev
    - libx264-dev
    - libx265-dev
    - nasm
    - texinfo
    - wget
    - yasm
    - zlib1g-dev
  tasks:
  - include: tasks/compfuzor.includes type=src
