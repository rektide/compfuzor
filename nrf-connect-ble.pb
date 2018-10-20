---
- hosts: all
  vars:
    TYPE: nrf-connect-blue
    INSTANCE: git
    REPO: https://github.com/NordicSemiconductor/pc-nrfconnect-ble
    BINS:
    - name: build.sh
      run: True
      exec: |
        npm install
  tasks:
  - include: tasks/compfuzor.includes type=src
  
