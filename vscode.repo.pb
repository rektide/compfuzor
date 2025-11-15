---
- hosts: all
  vars:
    TYPE: vscode
    INSTANCE: main
    APT_KEYRING_URL: https://packages.microsoft.com/keys/microsoft.asc 
    APT_KEYRING_DEARMOR: True
    APT_REPO: https://packages.microsoft.com/repos/vscode
    APT_COMPONENT: main
    APT_DISTRIBUTION: stable
    BINS:
      - name: install-ext.sh
        content: |
          while read -r line; do
            [[ "$line" =~ ^#.*$ ]] && continue
            code --install-extension $line
          done < $DIR/etc/extensions.list 
    ETC_FILES:
      - name: extensions.list
        content: |
          sourcegraph.amp
          eamodio.gitlens
          ms-vscode-remote.remote-containers
          GitHub.vscode-pull-request-github
          ecmel.vscode-html-css
          MS-vsliveshare.vsliveshare
          christian-kohler.path-intellisense
          EditorConfig.EditorConfig
          #yzhang.markdown-all-in-one
          unifiedjs.vscode-mdx
          #oderwat.indent-rainbow
          #DotJoshJohnson.xml
          redhat.vscode-xml
          redhat.vscode-yaml
          ms-kubernetes-tools.vscode-kubernetes-tools
          #ms-vscode.vscode-typescript-next
          GitHub.vscode-github-actions
          rust-lang.rust-analyzer
          4ops.terraform
          DigitalBrainstem.javascript-ejs-support
          denoland.vscode-deno
          slevesque.shader
          vadimcn.vscode-lldb
          dbaeumer.vscode-eslint
          vscjava.vscode-gradle
          ms-vscode.hexeditor
          vscjava.vscode-maven
          esbenp.prettier-vscode
          bmealhouse.shifty
          # ai
          #saoudrizwan.claude-dev
          RooVeterinaryInc.roo-cline
          Upstash.context7-mcp
          # colors/themes
          htmllessonsru.simple-random-theme
          monokai.theme-monokai-pro-vscode
          akamud.vscode-theme-onedark
          dracula-theme.theme-dracula
          daylerees.rainglow
          RobbOwen.synthwave-vscode
          liviuschera.noctis
          arcticicestudio.nord-visual-studio-code
  tasks:
    - import_tasks: tasks/compfuzor.includes
