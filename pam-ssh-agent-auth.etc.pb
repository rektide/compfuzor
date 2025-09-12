---
- hosts: all
  vars:
    TYPE: pam-ssh-agent-auth
    INSTANCE: main
    PKGS:
      - libpam-ssh-agent-auth
    ETC_FILES:
      - name: sudoers
        content: |
          Defaults env_keep += "SSH_AGENT_PID SSH_AUTH_SOCK"
      - name: pam
        content: |
          auth sufficient pam_ssh_agent_auth.so file=$AUTHORIZED_KEYS
    BINS:
      - name: install.sh
        run: True
        become: True
        content: |
          cat $DIR/etc/pam | envsubst | sudo block-in-file -C file /etc/pam.d/pam-ssh-agent-auth
          echo "@include pam-ssh-agent-auth" | sudo block-in-file -n "$NAME" -C file -b "^@include common-auth" /etc/pam.d/sudo
          cat $DIR/etc/sudoers | sudo block-in-file -n "$NAME" -C file /etc/sudoers.d/$NAME
    ENV:
      AUTHORIZED_KEYS: "{{file}}"
    #file: /etc/ssh/sudoers_authorized_keys
    file: "~/.ssh/authorized_keys"
  tasks:
    - include: tasks/compfuzor.includes type=etc
