---
- hosts: all
  gather_facts: False
  vars:
    TYPE: linux
    INSTANCE: 3.19
    TGZ: "https://www.kernel.org/pub/linux/kernel/v3.x/linux-{{INSTANCE}}.tar.xz"
    SRCS_DIR: "/usr/src"
  tasks:
  - include: tasks/compfuzor.includes type=src
  - shell: chdir="{{SRCS_DIR}}" tar xaf "linux-{{INSTANCE}}.tar.xz" --strip-components=1
