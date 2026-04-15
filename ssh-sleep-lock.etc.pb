---
- hosts: all
  vars:
    USERMODE: True
    SYSTEMD_UNITS:
      Description: Lock SSH agent on sleep via D-Bus PrepareForSleep
    SYSTEMD_SERVICES:
      ExecStart: "{{DIR}}/bin/ssh-sleep-lock"
      Environment: "SSH_AUTH_SOCK=%t/ssh-agent.sock"
      RestartSec: 3
    BINS:
      - name: ssh-sleep-lock
        basedir: False
        content: |
          dbus-monitor --system --profile "type='signal',sender='org.freedesktop.login1',interface='org.freedesktop.login1.Manager',member='PrepareForSleep'" 2>/dev/null | grep --line-buffered PrepareForSleep | while read -r _; do
              ssh-add -D 2>/dev/null
          done
  tasks:
    - import_tasks: tasks/compfuzor.includes
