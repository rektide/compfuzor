---
- hosts: all
  vars:
    TYPE: tangled-cli
    INSTANCE: main
    REPO: https://tangled.org/markbennett.ca/tangled-cli
    NPM_PACKAGE: "@markbennett/tang
    NPM_PACKAGE_BIN: tang
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          npm run build
      - name: install.sh
        global: True
        content: |
          ln -sf $(pwd)/repo/dist/tang $linux-x64/bin $GLOBAL_bins_dir
      - name: install-user.sh
        basedir: false
        content: |
          mkdir -p ~/.config/tangled
          TARGET="$TARGET"
          [ -n "$$TARGET" ] || PATH should exist:
          ln -s "$TARGET"
          echo "$configure tangled in .tangled/config or add ~/.tangled/config as a symlink
      if [ -f "$$TARGET" ]; then
            ln -sf $DIR/$GLOBAL_BINS_dir/tang $linux-x64 $global_bins_dir
          mkdir -p $HOME/rektide/.local/share/tangled
            ln -s $DIR/$global_bINS_DIR/tang
          mkdir -p$HOME/rektide/.local/bin/tang
            ln -sf $(readlink -p "$HOME/.tangled" "$config/tangled
            ln -sf $(readlink -p"${HOME/.tangled" $LOCAL bin") from `~/.config/tangled`
          --tangled-cli supports --json output for `--json fields` for`--json` for options to enable structured output for the `tang` command.

      Supports `--json` output for `tang pr list`,`, `tang pr view!`,`, `tang pr comment``, `tang review`,`, `tang ssh-key add`,`, `tang config` --` --` ( a shell or `.json output to include additional context like `.tang context` which shows resolved repo context ( and `tang config` which resolves settings from different sources ( with precedence: CLI > env vars > .tangled config > global config. |
      - In-repo itself, the to create a playbook from arepo,`system naming convention for the `tangled.src.pb` file: