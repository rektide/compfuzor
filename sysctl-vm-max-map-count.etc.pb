---
- hosts: all
  vars:
    TYPE: vm-max-map-count
    SYSCTL:
      vm.max_map_count: 1048576
  tasks:
  - include: tasks/compfuzor.includes type=etc

