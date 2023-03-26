- hosts: all
  vars:
    TYPE: scoop-nerd-fonts
    INSTANCE: main
  tasks:
    - name: add nerd-fonts bucket
      community.windows.win_scoop_bucket:
        name: nerd-fonts
      failed_when: nerd_bucket.stdout is not search ("already exists")
      changed_when: nerd_bucket.stdout is not search ("already exists")
      register: nerd_bucket
    - name: install nerd-fonts
      community.windows.win_scoop:
        name:
          - AnonymousPro-NF
          - FiraCode-NF
          - Hack-NF
          - Inconsolata-NF
          - Iosevka-NF
          - JetBrainsMono-NF
          - ProggyClean-NF
          - SourceCodePro-NF
          - Terminus-NF
          - VictorMono-NF
          #- AnonymousPro-NF-Mono
          #- FiraCode-NF-Mono
          #- Hack-NF-Mono
          #- Inconsolata-NF-Mono
          #- Iosevka-NF-Mono
          #- JetBrainsMono-NF-Mono
          #- SourceCodePro-NF-Mono
          #- Terminus-NF-Mono
          #- VictorMono-NF-Mono
        state: "{{nerd_state|default('present')}}"
