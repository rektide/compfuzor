---
- hosts: all
  vars:
    TYPE: waydroid-13
    INSTANCE: git
    REPO: https://github.com/gmankab/waydroid
    GET_URLS: 
      - https://github.com/gmankab/waydroid/releases/download/jul-12-2024/system.img
      - https://github.com/gmankab/waydroid/releases/download/jul-12-2024/vendor.img
    ENVS:
      INIT_ARGS: "-s GAPPS"
    BINS:
      - name: init-11.sh
        exec: |
          sudo waydroid init --system_channel=https://ota.waydro.id/system --vendor_channel=https://ota.waydro.id/vendor -f $INIT_ARGS
          sudo waydroid update
      - name: init-13.sh
        exec:
          sudo waydroid init -f -i $DIR/repo $INIT_ARGS
      - name: clean.sh
        exec: |
          rm -rf \
            /etc/waydroid-extra \
            /var/lib/waydroid \
            $HOME/.waydroid \
            ~/waydroid \
            ~/.share/waydroid \
            ~/.local/share/applications/*aydroid* \
            ~/.local/share/waydroid
  tasks:
    - import_tasks: tasks/compfuzor.includes
