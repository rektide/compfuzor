---
- hosts: all
  user: rektide
  vars:
    TYPE: rygel
    INSTANCE: main
    DIR_BYPASS: True
    USERMODE: True
    ETC_FILES:
    - rygel.conf
  tasks:
  - include: tasks/compfuzor.includes type="opt"
  - copy: src=files/pulseaudio/client.conf dest={{XDG_CONFIG_DIR}}/pulse/client.conf
  - file: src={{ETC}}/rygel.conf dest={{XDG_CONFIG_DIR}}/rygel.conf state=link
