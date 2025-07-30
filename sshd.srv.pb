---
- host: all
  vars:
    TYPE: sshd
    INSTANCE: main
    BIN:
      - name: install.sh
        exec: |
	  sudo systemctl enable sshd
	  sudo systemctl start sshd
  tasks:
    - import_tasks: tasks/compfuzor.includes
