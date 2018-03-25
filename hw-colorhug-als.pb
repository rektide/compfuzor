---
- hosts: all
  vars:
    TYPE: hw-colorhug-als
    INSTANCE: git
    REPOS:
    - "https://github.com/hughski/colorhug-als-firmware" # basically impossible to build. :'(
    GIT_VERSION: sensor-hid
    GET_URLS:
    - "http://ww1.microchip.com/downloads/en/DeviceDoc/xc8-v1.34-full-install-linux-installer.run"
    - "http://ww1.microchip.com/downloads/en/softwarelibrary/microchip-libraries-for-applications-v2013-06-15-linux-installer.run"
    #- "https://secure-lvfs.rhcloud.com/downloads/8dbdd54c712b33f72d866ce3b23b3ceed3ad494d-hughski-colorhug-als-4.0.3.cab" # awful shameful fallback
    PKGS:
    - fwupd
    - gcab
    # getting libgusb undefined symbol errors, creating colorhug-client.src.pb
    #- colorhug-client
  tasks:
  - include: tasks/compfuzor.includes type=src
