---
- hosts: all
  tasks:
   - name: install many things
     chocolatey.chocolatey.win_chocolatey:
       state: latest
       name:
        - adb
        - alacritty # terminal
        - autohotkey
        - bonjour
        #- cerebro # launcher
        - curl
        - Cygwin
        - cyg-get
        - darktable
        - deno
        - displayfusion.portable # display config tweaks
        - everything.portable # file finder
        - everythingpowertoys #file finder tweaks
        - fd
        - flow-launcher
        - gajim
        - git
        - google-cast-chrome
        - GoogleChrome
        - googledrive
        - gstreamer
        - honeyview.portable
        - hwinfo.portable
        - inkscape
        - latencymon
        - k-litecodecpackfull
        - libreoffice-fresh
        #- microsoft-windows-terminal # often already installed, and this seems broken
        - mpc-hc-clsid2
        - mpc-be
        - mumble
        - neovim
        - nodejs
        - notepadplusplus
        - onecommander
        #- openssh # ick! super old!
        - powertoys
        - processhacker.portable
        - procexp
        - procmon
        - putty
        - ripgrep
        - ripcord
        - scrivner # bookwriting
        - scrcpy
        - sshfs
        - steam # gaming
        - tailscale # vpn
        - tightvnc # remote desktop
        - unifiedremote
        - vim # editing
        - vlc
        - vscode
        - vscode-chrome-debug
        - vscode-eslint
        - vscode-gitignore
        - vscode-gitlens
        - vscode-intellicode
        - vscode-kubernetes-tools
        #- vscode-live-share-audio
        - vscode-markdownlint
        - vscode-prettier
        - vscode-vsliveshare
        #- vscode-vsonline
        - windirstat
        - wsl2
        - zoom
        - obs-studio.portable
        #- obs-virtualcam
        - obs-ndi
        - obs-move-transition
        - touchportal
        - sunshine
        - droidcam-obs-plugin
        - sony-imaging-edge-webcam
     #become: True
