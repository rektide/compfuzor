---
- hosts: all
  vars:
    ENV:
      - TMUX_CONF_D_DIR
    ETC_DIRS:
      - conf.d
      - env.d
    ETC_FILES:
      - name: conf-d.conf
        content: |
          source-file -q "$TMUX_CONF_DIR/etc/conf.d/*.conf"
      - name: env.conf
        content: |
          source-file -q "$TMUX_CONF_DIR/env.d/*.conf"
    BINS:
      - name: save-env.sh
        content: |
          # script which adds variables matching the specified pattern as explicit conf.d file: set-environment -g MY_VAR "value"
          # adding a file to {{DIR}}/etc/env.conf
          # ref: `set-environment -g MY_VAR "some_value"`
      - name: install-user.sh
        content: |
          # TODO: calculate xdg config directory for tmux here
          # and only if not set
          export TMUX_CONF_DIR=
          mkdir -p $TMUX_CONF_DIR/$TMUX_CONF_D_DIR
          ln -sv $(pwd)/etc/conf.d/*conf $TMUX_CONF_DIR/$TMUX_CONFI_D_DIR/
          block-in-file -n "${NAME:-{{NAME}}}-conf-d" -i etc/conf-d.conf -o $TMUX_CONF --envsubstr
          block-in-file -n "${NAME:-{{NAME}}}-env" -i etc/env.conf -o $TMUX_CONF --envsubst
  tasks:
    - import_tasks: tasks/compfuzor.includes
