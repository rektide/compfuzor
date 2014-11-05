---
- hosts: all
  gather_facts: False
  vars:
    NAME: xdg-dirs
    DIR: '/etc/xdg'
    ENV:
      XDG_DOCUMENTS_DIR: "$HOME/docs"
      XDG_DESKTOP_DIR: "$HOME/docs/desktop"
      XDG_DOWNLOAD_DIR: "$HOME/docs/download"
      XDG_MUSIC_DIR: "$HOME/docs/music"
      XDG_PICTURES_DIR: "$HOME/docs/picture"
      XDG_PUBLICSHARE_DIR: "$HOME/docs/public"
      XDG_TEMPLATES_DIR: "$HOME/docs/templates"
      XDG_VIDEOS_DIR: "$HOME/docs/video"
    LINKS:
      'user-dirs.defaults': 'env'
  tasks:
  #- include: tasks/compfuzor.includes
  - include: tasks/compfuzor/vars_env.tasks
  - file: path="{{DIR}}/user-dirs.defaults" state=absent
  - include: tasks/compfuzor/fs_env.tasks
  - include: tasks/compfuzor/links.tasks
