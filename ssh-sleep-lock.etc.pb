---
- hosts: all
  vars:
    USERMODE: True
    SYSTEMD_UNITS:
      Description: Lock SSH agent before sleep
      Before: sleep.target suspend.target hibernate.target hybrid-sleep.target
    SYSTEMD_SERVICES:
      Type: oneshot
      ExecStart: /usr/bin/ssh-add -D
      Environment: "SSH_AUTH_SOCK=%t/ssh-agent.sock"
    SYSTEMD_INSTALLS:
      WantedBy: sleep.target suspend.target hibernate.target hybrid-sleep.target
  tasks:
    - import_tasks: tasks/compfuzor.includes
