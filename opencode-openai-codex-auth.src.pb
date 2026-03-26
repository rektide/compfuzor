---
- hosts: all
  vars:
    REPO: https://github.com/numman-ali/opencode-openai-codex-auth
    NODEJS: True
    INSTALL_BYPASS: True
    BINS:
      - name: install-user.sh
        basedir: repo
        content: |
          npx .
  tasks:
    - import_tasks: tasks/compfuzor.includes
