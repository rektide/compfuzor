---
- hosts: all
  vars:
    TYPE: hw-tizen
    INSTANCE: 2.4
    GET_URLS:
    - http://usa.sdk-dl.tizen.org/tizen-web-ide_TizenSDK_2.4.0_Rev8_usa_ubuntu-64.bin
  tasks:
  - include: tasks/compfuzor.includes
