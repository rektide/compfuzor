---
- hosts: all
  vars:
    REPO: https://github.com/cdk8s-team/cdk8s-cli
    TOOL_VERSIONS:
      yarn: True
    ENV: True
    BINS:
      - name: build.sh
        basedir: repo
        content: |
          yarn install
          yarn compile
      - name: install.sh
        content:

  tasks:
    - import_tasks: tasks/compfuzor.includes
