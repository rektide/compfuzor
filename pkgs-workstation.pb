---
- hosts: all
  gather_facts: False
  vars:
    NAME: pkgs-workstation
    PKGSETS:
    - BASE
    - WORKSTATION
    - WORKSTATION_X
    - DEVEL
    - DEBDEV
    - AUDIO
    - BT
    - BT_X
    - RYGEL
    - RYGEL_X
    - JACK
    - JACK_PLUGINS
    - JACK_X
    - MEDIA
    - MEDIA_X
  tasks:
  - include: tasks/compfuzor.includes
