---
- hosts: all
  vars:
    TYPE: emscripten
    INSTANCE: git
    REPO: git://github.com/kripken/emscripten.git
    cores: 6
    fastcomp: "{{SRCS_DIR}}/{{TYPE}}-fastcomp-{{INSTANCE}}"
  tasks:
  - include: tasks/compfuzor.includes type=src
  - git: repo=https://github.com/kripken/emscripten-fastcomp dest="{{fastcomp}}"
  - git: repo=https://github.com/kripken/emscripten-fastcomp-clang dest="{{fastcomp}}/tools/clang"
  - file: path="{{fastcomp}}/build" state=directory
  - shell: chdir="{{fastcomp}}/build" ../configure --enable-optimized --disable-assertions -enable-targets=host,js
  - shell: chdir="{{fastcomp}}/build" make -j {{cores}}
