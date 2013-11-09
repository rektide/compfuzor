---
- hosts: all
  gather_facts: False
  vars:
    TYPE: snowmix
    INSTANCE: git
    #REPO: git://git.code.sf.net/p/snowmix/code
    PKGS:
    - tcl8.5-dev
    - tk8.5
    - tcl8.5
    - libosmesa6-dev
    - libsdl1.2-dev
    - libgtk-3-0
    - libgtk-3-dev
    - libgstreamer0.10-dev 
    - gstreamer-tools
    version: 0.4.2
    file: "http://downloads.sourceforge.net/project/snowmix/Snowmix-{{version}}.tar.gz?r=http%3A%2F%2Fsourceforge.net%2Fprojects%2Fsnowmix%2Ffiles%2F%3Fsource%3Dnavbar&ts=1383968317&use_mirror=softlayer-dal"
    bad: "Snowmix-{{version}}"
    nice: "snowmix-{{version}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
  - set_fact: src_dir="{{DIR}}"
  - get_url: url="{{file}}" dest="{{SRCS_DIR}}/{{nice}}.tgz"
  - shell: chdir="{{SRCS_DIR}}" tar -xvzf "{{nice}}.tgz"
  - shell: chdir="{{SRCS_DIR}}" test -d "{{bad}}"; echo $?
    register: clean
  - file: path="{{DIR}}" state=directory
 
  # ANSIBLE FAIL #1 
  #- shell: chdir="{{SRCS_DIR}}/{{bad}}" find . -type f -exec echo {{bad}}/{} {{NAME}}/{} \;|tr "\n" " "
  #  register: raw
  #- shell: chdir="{{SRCS_DIR}}" mv {{raw.stdout}}

  # ANSIBLE FAIL #2
  #- shell: chdir="{{SRCS_DIR}}/{{bad}}" find . -type f -exec echo "{{bad}}/{}" "{{NAME}}/{}" \;
  #  register: raw
  #- shell: chdir="{{SRCS_DIR}}" mv "{{bad}}/{{item}}" "{{NAME}}/{{item}}" -f
  #  with_lines: raw.stdout

  - shell: chdir="{{SRCS_DIR}}" cp -aur "{{bad}}"/* "{{DIR}}/"

  - file: path="{{SRCS_DIR}}/{{bad}}" state=absent
    when: clean.stdout|int != 0
  - include: tasks/compfuzor.includes type=opt 
  - shell: cp -aurv "{{src_dir}}/fonts/Eurosti.ttf" "{{FONTS_TTF}}/Eurosti.ttf"
  - shell: chdir="{{src_dir}}" ./bootstrap
  - shell: chdir="{{src_dir}}" LIBS=-lpng12 ./configure --prefix="{{DIR}}"
  - shell: chdir="{{src_dir}}" make
  - shell: chdir="{{src_dir}}" make install
