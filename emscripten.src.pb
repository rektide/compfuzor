---
- hosts: all
  vars:
    TYPE: emscripten
    INSTANCE: git
    REPO: https://github.com/kripken/emscripten.git
    REPOS: 
      llvm: https://github.com/kripken/emscripten-fastcomp 
      "fastcomp-clang": https://github.com/kripken/emscripten-fastcomp-clang 
    LINKS:
      "{{DIR}}/llvm/tools/clang": "{{DIR}}/fastcomp-clang"
    BINS:
    - name: "make-llvm"
      run: True
    cores: 8
  tasks:
  - include: tasks/compfuzor.includes type=src
