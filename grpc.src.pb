---
- hosts: all
  vars:
    TYPE: grpc
    INSTANCE: git
    REPO: https://github.com/grpc/grpc
    BINS:
    - exec: make
      pwd: "{{DIR}}/repo"
    - exec: make install prefix={{DIR}}
      pwd: "{{DIR}}/repo"
    - exec: npm install
      pwd: "{{DIR}}/repo"
    PKGCONFIG: True
    ENV:
      ldflags: "-l{{DIR}}/lib"
      cflags: "-I{{DIR}}/include"
      cppflags: "-I{{DIR}}/include"
      cxxflags: "-I{{DIR}}/include"
      ld_library_path: "$LD_LIBRARY_PATH:{{DIR}}/lib"
      path: "{{DIR}}/bin:$PATH"
  tasks:
  - include: tasks/compfuzor.includes type=opt
