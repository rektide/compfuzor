---
- hosts: all
  vars:
    TYPE: hw-silego-greenpak
    INSTANCE: main
    ZIP: http://www.silego.com/uploads/resources/GP1-5_Designer_v5.09.001_LNX_Setup.zip
    PKGS:
    - libcdt5
    - libcgraph6
    - libgvc6
    - libicu52
    - libxdot4
    - libpathplan4
    - libgts-0.7-5
  tasks:
  - include: tasks/compfuzor.includes
  - command: dpkg -i "{{DIR}}/GP1-5_Designer_v5.09.001_LNX_Setup/greenpak-designer_5.09-1~Debian~jessie_amd64.deb"
