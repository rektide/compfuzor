---
- hosts: all
  vars:
    TYPE: sugar
    INSTANCE: git
    PKGS:
    - python3-empy
    - python-six
    - python3-six
    - python-gtk2-dev
    - libasound2-dev
    - librsvg2-dev
    - icon-naming-utils
    REPOS: 
    - https://github.com/sugarlabs/sugar
    - https://github.com/sugarlabs/sugar-artwork
    - https://github.com/sugarlabs/sugar-datastore
    - https://github.com/sugarlabs/sugar-toolkit
    - https://github.com/sugarlabs/sugar-toolkit-gtk3
    - https://github.com/sugarlabs/terminal-activity
    # supplemental:
    - https://github.com/sugarlabs/jukebox-activity
    - https://github.com/sugarlabs/iq-activity
    - https://github.com/sugarlabs/clock-activity
    - https://github.com/sugarlabs/speak
    - https://github.com/sugarlabs/story
    BIN:
    - name: build.sh
      exec: |
        DIR=`pwd`
        cd $DIR/sugar-toolkit
        ./autogen.sh
        make
        sudo make install
        
        cd $DIR/sugar-toolkit-gtk3
        ./autogen.sh
        make
        sudo make install
        
        cd $DIR/sugar-artwork
        ./autogen.sh
        make
        sudo make install
        
        cd $DIR/sugar-toolkit-datastore
        ./autogen.sh
        make
        sudo make install
        
        cd $DIR/sugar
        ./autogen.sh
        make
        sudo make install
  tasks:
  - include: tasks/compfuzor.includes type=src
