---
- hosts: all
  vars:
    TYPE: opencode-skills
    INSTANCE: git
    REPO: https://github.com/malhashemi/opencode-skills
    ETC_FILES:
      - name: opencode-skills.json
        json:
          plugin:
            - opencode-skills
  tasks:
    - import_tasks: tasks/compfuzor.includes

