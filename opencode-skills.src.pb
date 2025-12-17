---
- hosts: all
  vars:
    TYPE: opencode-skills
    INSTANCE: git
    REPO: https://github.com/malhashemi/opencode-skills
    ENV: True
    ETC_DIRS:
      - hello-world
    ETC_FILES:
      - name: opencode-skills.json
        json:
          plugin:
            - opencode-skills
      - name: hello-world/SKILL.md
        content: |
          ---
          name: hello-world # Must match directory name
          description: A sample skill to test that opencode-skills is working
          license: MIT
          allowed-tools:
           - bash
          metadata:
            version: "1.0"
          ---
          
          # hello world skill
          
          This skill greets the user.
          
          ## Instructions
          
          1. Use bash to get the current $USER
          2. Tell the user `Hello, $USER`.
          3. Finally, give them a good affirmation of encouragement. Tell them something nice to motivate them.
    BINS:
      - name: install-skill.sh
        basedir: False
        content: |
          mkdir -p ~/.config/opencode/skills

          SKILL_DIR="$1"
          [ -n "$SKILL_DIR" ] && SKILL_DIR="$DIR/etc/hello-world"
          ln -sfv $(realpath --no-symlinks $SKILL_DIR) $HOME/.config/opencode/skills/
  tasks:
    - import_tasks: tasks/compfuzor.includes

