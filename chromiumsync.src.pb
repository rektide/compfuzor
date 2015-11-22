---
- hosts: all
  gather_facts: false
  vars:
    TYPE: chromiumsync
    INSTANNCE: git
    REPO: https://chromium.googlesource.com/chromium/src
    GIT_DEPTH: 1
  tasks:
  - include: tasks/compfuzor.includes type=src
  # https://chromium.googlesource.com/chromium/src/net/tools/testserver/+/b379b41ea067f65e8abd200fca9d40ec60d55147/chromiumsync.py
