---
- hosts: all
  vars:
    TYPE: cilium
    INSTANCE: "{{ DOMAIN|replace('.', '-') }}"
    
