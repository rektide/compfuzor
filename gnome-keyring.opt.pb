---
# supposeldy console-friendly, based on https://wiki.archlinux.org/title/GNOME/Keyring
# still not really working for me though.
- hosts: all
  vars:
    TYPE: gnome-keyring-daemon
    INSTANCE: main
    ETC_DIRS:
      - pam.d
    ETC_FILES:
      - name: pam.d/passwd
        content: |
          # automatically change keyring password with user password
          password optional pam_gnome_keyring.so
      - name: pam.d/login-auth
        content: |
          # unlock on login
          auth optional pam_gnome_keyring.so
      - name: pam.d/login-session
        content: |
          # unlock in each session
          session optional pam_gnome_keyring.so auto_start
    BINS:
      - name: install.sh
        content: |
          bif=$(command -v block-in-file)
          $bif -n $NAME -i $DIR/etc/pam.d/passwd /etc/pam.d/passwd
          $bif -n $NAME-auth -i $DIR/etc/pam.d/login-auth -a '^auth' /etc/pam.d/login
          $bif -n $NAME-session -i $DIR/etc/pam.d/login-session -a '^session' /etc/pam.d/login
    ENV:
      STUB: entry
  tasks:
    - include: tasks/compfuzor.includes type=opt
