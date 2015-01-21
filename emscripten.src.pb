---
- hosts: all
  vars:
    TYPE: emscripten
    INSTANCE: git
    DIR: "{{SRC}}"
    REPOS: 
      llvm: https://github.com/kripken/emscripten-fastcomp 
      "fastcomp-clang": https://github.com/kripken/emscripten-fastcomp-clang 
      emscripten: https://github.com/kripken/emscripten.git
    LINKS:
      "{{DIR}}/llvm/tools/clang": "{{DIR}}/fastcomp-clang"
    BINS:
    - name: "make-llvm"
      run: True
  tasks:
  - include: tasks/compfuzor.includes type=src
