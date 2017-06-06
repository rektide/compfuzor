---
- hosts: all
  vars:
    TYPE: zephyr
    INSTANCE: git
    REPO: https://github.com/zephyrproject-rtos/zephyr
  tasks:
  - include: tasks/compfuzor.includes type=src
