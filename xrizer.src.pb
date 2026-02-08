---
- hosts: all
  vars:
    REPO: https://github.com/Supreeeme/xrizer
    RUST: True
    CARGO_BUID: xbuild
    BINS:
      - name: install-user.sh
        content: |
          # removedriver
          ~/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh adddriver {{BUILD_DIR}}/steamvr-monado
          ~/.steam/steam/steamapps/common/SteamVR/bin/vrpathreg.sh 
  tasks:
    - import_tasks: tasks/compfuzor.includes
