---
- hosts: all
  vars:
    TYPE: nodemcu
    INSTANCE: git
    REPOS:
      esp-open-sdk: "https://github.com/pfalcon/esp-open-sdk"
      firmware: "https://github.com/nodemcu/nodemcu-firmware"
      esptool: "https://github.com/themadinventor/esptool"
      #esplorer: "https://github.com/4refr0nt/ESPlorer"
      #rsyntaxtextarea: "https://github.com/bobbylight/RSyntaxTextArea" # used by esplorer
      #java-simple-serial-connector: "https://github.com/scream3r/java-simple-serial-connector" # used by esplorer
      #espressif-sdk zip http://bbs.espressif.com/download/file.php?id=1079
    ENV:
      library_path: "{{DIR}}/repo/esp-open-sdk/lib"
      cpath: "{{DIR}}/repo/esp-open-sdk/include"
    BINS:
    - name: build.sh
    PKGS:
    - gperf
    - texinfo
  tasks:
  - include: tasks/compfuzor.includes
   
