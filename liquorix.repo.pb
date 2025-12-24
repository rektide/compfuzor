---
- hosts: all
  vars:
    INSTANCE: etc
    APT_REPO: https://liquorix.net/debian 
    APT_KEYRING_URL: https://liquorix.net/liquorix-keyring.gpg
    # $codename main\ndeb-src http://liquorix.net/debian $codename main\n\n# Mirrors:\n#\n# Unit193 - France\n# deb http://mirror.unit193.net/liquorix $codename main\n# deb-src http://mirror.unit193.net/liquorix $codename main" | sudo tee /etc/apt/sources.list.d/liquorix.list && curl https://liquorix.net/linux-liquorix.pub | sudo apt-key add - && sudo apt-get update
  tasks:
    - import_tasks: tasks/compfuzor.includes
