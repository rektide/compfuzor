---
- hosts: all
  vars:
    TYPE: skype
    DIR_BYPASS: True
    PKGS:
    - libasound2-plugins
    - libqtwebkit4
    - libqt4-dbus
    deb: http://www.skype.com/go/getskype-linux-deb
  tasks:
  - include: tasks/compfuzor.includes
  - get_url: url="{{deb}}" dest="/tmp/skype.deb"
  - shell: dpkg -i /tmp/skype.deb
    sudo: True
  - file: path="/tmp/skype.deb" state=absent
