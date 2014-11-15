---
- hosts: all
  gather_facts: False
  vars:
    NAME: machine
    INSTANCE: firstpost
    usr: 
  tasks:
  - include: tasks/cmpfuzor.includes
  # allocate btrfs space
  # create .machine
  # ovs device for .machine
