- hosts: all
  vars:
    TYPE: nerd-fonts
    INSTANCE: main
    SRC_DIR: True
    BINS:
      - name: fetch.sh
        basedir: src
        #run: True
        exec: |
          while read -d, -a font
          do
            wget ${FONTS_URL}/v${RELEASE}/${font}.tar.xz
          done <<< "$FONTS"
      - name: install.sh
        exec: |
          mkdir -p $DEST
          cd $DEST
          while read -d, -a font
          do
            tar xvaf ${DIR}/src/$font.tar.xz --touch --no-overwrite-dir --no-same-permissions --no-same-owner --exclude '*.md' --exclude '*.txt' --exclude LICENSE
          done <<< "$FONTS"
          # rebuild font cache
          fc-cache -fv
    ENV:
      FONTS: "{{fonts|join(',')}}"
      FONTS_URL: https://github.com/ryanoasis/nerd-fonts/releases/download/
      RELEASE: "{{release}}"
      #DEST: "$HOME/.local/share/fonts"
      DEST: /usr/share/fonts
    release: 3.1.1
    fonts:
      - 0xProto
      - 3270
      - Agave
      - AnonymousPro
      - Arimo
      - AurulentSansMono
      - CascadiaMono
      - DaddyTimeMono
      - EnvyCodeR
      - FantasqueSansMono
      - FiraCode
      - Go-Mono
      - Inconsolata
      - Iosevka
      - IosevkaTerm
      - Lekton
      - JetBrainsMono
      - MartianMono
      - Monofur
      - Meslo
      - Monaspace
      - Mononoki
      - MPlus
      - ProFont
      - ProggyClean
      - RobotoMono
      - VictorMono
  tasks:
    - include: tasks/compfuzor.includes
