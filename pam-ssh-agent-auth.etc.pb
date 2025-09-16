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
          cat $DIR/etc/sudoers | envsubst | sudo block-in-file -n "$NAME" -C -o /etc/sudoers.d/pam-ssh-agent-auth
          cat $DIR/etc/pam | envsubst | sudo block-in-file -n "$NAME" -C -o /etc/pam.d/pam-ssh-agent-auth
          echo "@include pam-ssh-agent-auth" | sudo block-in-file -n "$NAME" -b "^@include common-auth" /etc/pam.d/sudo
      - name: install-key.sh
        basedir: False
        content: |
          [ -z "$1" ] && echo "missing public key" >&2 && exit 1
          cat $1 | sudo tee /etc/ssh/sudoers_authorized_keys
    ENV:
      AUTHORIZED_KEYS: "{{file}}"
    file: /etc/ssh/sudoers_authorized_keys
    #file: "~/.ssh/authorized_keys"
  tasks:
    - import_tasks: tasks/compfuzor.includes
