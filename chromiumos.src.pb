---
# primarily for sommelier for now but maybe more latter. all credit to two works:
# - https://alyssa.is/using-virtio-wl/
# - https://github.com/skycocker/chromebrew/blob/master/packages/sommelier.rb
# 
- hosts: all
  vars:
    TYPE: chromiumos-platform
    INSTANCE: git
    REPO: https://chromium.googlesource.com/chromiumos/platform2
    GET_URLS:
      virtwl.h: "https://chromium.googlesource.com/chromiumos/third_party/kernel/+/5d641a7b7b64664230d2fd2aa1e74dd792b8b7bf/include/uapi/linux/virtwl.h?format=TEXT"
  tasks:
  - include: tasks/compfuzor.includes type=src
