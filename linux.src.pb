---
- hosts: all
  gather_facts: False
  vars:
    TYPE: linux
    INSTANCE: 4.1-rc6
    TGZ: "https://www.kernel.org/pub/linux/kernel/v4.x/testing/linux-{{INSTANCE}}.tar.xz"
    SRCS_DIR: "/usr/src"
  tasks:
  - include: tasks/compfuzor.includes type=src
  # fix config file to strip debug
  # INSTALL_MOD_STRIP=1
