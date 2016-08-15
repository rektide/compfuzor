---
# https://wiki.tizen.org/wiki/ARTIK_5_for_Tizen_3.0
- hosts: all
  vars:
    TYPE: hw-samsung-artik
    INSTANCE: main
    GET_URLS:
    - "http://download.tizen.org/snapshots/tizen/tv/latest/images/arm-wayland/tv-wayland-armv7l-odroidu3/tizen-tv_20160812.2_tv-wayland-armv7l-odroidu3.tar.gz"
  tasks:
  - include: tasks/compfuzor.includes
