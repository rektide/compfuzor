---
- hosts: all
  vars:
    REPO: https://github.com/sxyazi/yazi
    RUST: True
    PKGS:
     - ffmpeg
     - 7zip
     - jq
     - poppler-utils
     - fd-find
     - ripgrep
     - fzf
     - zoxide
     - imagemagick
  tasks:
    - import_tasks: tasks/compfuzor.includes

