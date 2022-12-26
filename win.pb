---
- hosts: all
  tasks:
   - name: install many things
     chocolatey.chocolatey.win_chocolatey:
       state: latest
       name:
        - alacritty
        - autohotkey
        - curl
        - Cygwin
        - cyg-get
        - gajim
        - git
        - google-cast-chrome
        - GoogleChrome
        - googledrive
        - gstreamer
        - inkscape
        - k-litecodecpack-standard
        - libreoffice-fresh
        #- microsoft-windows-terminal # often already installed, and this seems broken
        - mpc-hc-clsid2
        - mpc-be
        - mumble
        - notepadplusplus
        #- openssh # ick! super old!
        - procexp
        - procmon
        - putty
        - sshfs
        - steam
        - tailscale
        - tightvnc
        - vim
        - vlc
        - vscode
        - vscode-chrome-debug
        - vscode-eslint
        - vscode-gitignore
        - vscode-gitlens
        - vscode-intellicode
        - vscode-kubernetes-tools
        - vscode-live-share-audio
        - vscode-markdownlint
        - vscode-prettier
        - vscode-vsliveshare
        - vscode-vsonline
        - wsl2
        - zoom
     #become: True
