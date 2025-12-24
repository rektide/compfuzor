---
- hosts: all
  vars:
    TYPE: opencode
    INSTANCE: git
    REPO: https://github.com/sst/opencode
    TOOL_VERSIONS:
      bun: 1
      go: 1
    ETC_DIRS:
      - mcp
      - agent
    ETC_FILES:
      - name: base.json
        json:
          "$schema": "https://opencode.ai/config.json"
      - name: agent/review.md
        content: |
          ---
          description: Reviews code for quality and best practices
          mode: subagent
          tools:
            write: false
            edit: false
            bash: false
          ---

          You are in code review mode. Focus on:

          - Code quality and best practices
          - Potential bugs and edge cases
          - Performance implications
          - Security considerations

          Provide constructive feedback without making direct changes.
      - name: agent/docs-writer.md
        content: |
          ---
          description: Writes and maintains project documentation
          mode: subagent
          tools:
            bash: false
          ---

          You are a technical writer. Create clear, comprehensive documentation.

          Focus on:

          - Clear explanations
          - Proper structure
          - Code examples
          - User-friendly language
      - name: mcp/context7.json
        json:
          mcp:
            context7:
              enabled: true,
              type: "remote"
              url: "https://context7.liam.sh/mcp"
              headers:
                Authorization: "Bearer {env:CONTEXT7_API_KEY}"
      #- name: provider/openrouter.json
      #  json:
      #    provider:
      #      openrouter:
      #        options:
      #          apiKEy: "{env:OPENROUTER_API_KEY}"
    BINS:
      - name: build.sh
        basedir: packages/opencode
        content: |
          # for opencode-live
          bun install --frozen-lockfile
          # real build
          bun run build
      - name: config.sh
        content: |
          echo combining config
          jq -s 'reduce .[] as $item ({}; . * $item)' etc/base.json etc/mcp/*json > etc/opencode.json
      - name: install.sh
        content: |
          ln -sfv $(pwd)/packages/opencode/dist/opencode-linux-x64/bin/opencode $GLOBAL_BINS_DIR/
      # TODO: compfuzor helpers for installing content, automate this below
      - name: install-user.sh
        basedir: False
        content: |
          mkdir -p ~/.local/share/opencode/log

          [ -n "$TARGET" ] || TARGET="$HOME/.config/opencode"
          mkdir -p $(dirname $TARGET)
          ln -sv ${DIR}/etc $TARGET/
      - name: opencode-live
        basedir: False
        global: True
        content: |
          # note/beware that we also are pulling in env.exports
          exec bun run --cwd $DIR dev $(pwd)
    ENV:
      CONTEXT7_API_KEY: example-key
  tasks:
    - import_tasks: tasks/compfuzor.includes
