---
- hosts: all
  vars:
    TYPE: lutris
    INSTANCE: main
    APT_REPO: https://download.opensuse.org/repositories/home:/strycore/Debian_12/ 
    APT_DISTRIBUTION: "./"
    APT_COMPONENTS: []
    APT_KEYRING_URL: https://download.opensuse.org/repositories/home:/strycore/Debian_12/Release.key 
    APT_DEARMOR: True
    BINS:
  tasks:
    - import_tasks: tasks/compfuzor.includes


