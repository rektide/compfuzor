---
- hosts: all
  vars:
    TYPE: liquorix
    INSTANCE: main
    APT_REPO: http://liquorix.net/debian 
    # $codename main\ndeb-src http://liquorix.net/debian $codename main\n\n# Mirrors:\n#\n# Unit193 - France\n# deb http://mirror.unit193.net/liquorix $codename main\n# deb-src http://mirror.unit193.net/liquorix $codename main" | sudo tee /etc/apt/sources.list.d/liquorix.list && curl https://liquorix.net/linux-liquorix.pub | sudo apt-key add - && sudo apt-get update
  tasks:
  - include: tasks/compfuzor.includes type=etc
