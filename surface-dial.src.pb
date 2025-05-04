---
- hosts: all
  vars:
    TYPE: surface-dial
    INSTANCE: git
    REPO: https://github.com/daniel5151/surface-dial-linux
    PKGS:
      - libudev-dev
      - libevdev-dev
      - libhidapi-dev
    ENV:
      hi: ho
    BINS:
      - name: build.sh
        exec: |
          cargo build -p surface-dial-daemon --release
      - name: install-udev.sh
        exec: |
          # install the udev rules
          sudo cp ./install/10-uinput.rules /etc/udev/rules.d/10-uinput.rules
          sudo cp ./install/10-surface-dial.rules /etc/udev/rules.d/10-surface-dial.rules
          sudo udevadm control --reload
      - name: install-daemon.sh
        exec: |
          # install the daemon
          sudo ln -sv $(pwd)/target/release/surface-dial-daemon $GLOBAL_BINS_DIR/
      - name: install-user.sh
        exec: |
          cargo install --path .
          mkdir -p ~/.config/systemd/user/
          cp ./install/surface-dial.service ~/.config/systemd/user/surface-dial.service
          #mkdir -p ~/.config/systemd/user/surface-dial.service.d
          #echo '[Service]' > ~/.config/systemd/user/surface-dial.service.d/exec-path.conf
          #echo 'ExecStart' > ~/.config/systemd/user/surface-dial.service.d/exec-path.conf
          systemctl --user daemon-reload
          systemctl --user enable surface-dial.service
          systemctl --user start surface-dial.service
  tasks:
    - import_tasks: tasks/compfuzor.includes
