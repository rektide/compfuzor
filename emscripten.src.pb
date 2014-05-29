---
- hosts: all
  vars:
    TYPE: emscripten
    INSTANCE: git
    REPO: git://github.com/kripken/emscripten.git
    cores: 6
  tasks:
  - include: tasks/compfuzor.includes type=src
  - set_fact: fastcomp="{{SRCS_DIR}}/{{TYPE}}-fastcomp-{{INSTANCE}}"
  - git: repo=https://github.com/kripken/emscripten-fastcomp dest="{{fastcomp}}"
  - git: repo=https://github.com/kripken/emscripten-fastcomp-clang dest="{{fastcomp}}/tools/clang"
  - file: path="{{fastcomp}}/build" state=directory
  - shell: chdir="{{fastcomp}}/build" ../configure --enable-optimized --disable-assertions -enable-targets=host,js
  - shell: chdir="{{fastcomp}}/build" make -j {{cores}}
