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
  - include: tasks/xdg.vars.tasks
  - include: tasks/compfuzor.includes type="opt"
  - copy: src=files/pulseaudio/client.conf dest={{xdg_config_dir}}/pulse/client.conf
  - file: src={{ETC}}/rygel.conf dest={{xdg_config_dir}}/rygel.conf state=link
