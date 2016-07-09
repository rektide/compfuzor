---
- hosts: all
  vars:
    TYPE: net-ipv4-forward
    SYSCTL:
      net.ipv4.ip_forward: 1
  tasks:
  - include: tasks/compfuzor.includes type=etc

