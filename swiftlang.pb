---
- hosts: all
  vars:
    TYPE: swiftlang
    INSTANCE: main
    TGZ: "https://swift.org/builds/swift-3.0-preview-4/ubuntu1510/swift-3.0-PREVIEW-4/swift-3.0-PREVIEW-4-ubuntu15.10.tar.gz"
    PKGS:
    - curl
    - sqlite3
    - git-core
    - libffi-dev
    - python-setuptools
    - python-dev
    - python-pip
    - ninja-build
    ENV:
      PATH: "{{DIR}}/usr/bin:$PATH"
      CPATH: "{{DIR}}/usr/include:$CPATH"
      LD_LIBRARY_PATH: "{{DIR}}/usr/lib:$LD_LIBRARY_PATH"
      MANPATH: "{{DIR}}/usr/share/man:$MANPATH"
  tasks:
  - include: tasks/compfuzor.includes
