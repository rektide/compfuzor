---
- hosts: all
  vars:
    TYPE: ca
    INSTANCE: main
    domain:
    - net
    - yoyodyne
    organizationName: Yoyodyne Propulsion Systems
    stateOrProvinceName: DC
    countryName: US
    signing:
    - name: root
    - name: signing
  tasks:
  - include: tasks/compfuzor.includes type=srv
  - file: state=directory path={{VAR}}/{{item.name}}/private
    with_items: signing
  - file: state=directory path={{VAR}}/{{item.name}}/crl
    with_items: signing
  - file: state=directory path={{VAR}}/{{item.name}}/newcerts
    with_items: signing
  - file: state=directory path={{VAR}}/{{item.name}}/certs
    with_items: signing
