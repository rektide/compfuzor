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
      - mcp-enabled
      - mcp-disabled
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
          set -e
          dir={{DIR}}
          mkdir -p ${dir}/etc/mcp-enabled ${dir}/etc/mcp-disabled

          for json_file in ${dir}/etc/mcp/*.json; do
            filename=$(basename "$json_file")

            if [ -L "${dir}/etc/mcp-disabled/$filename" ]; then
              continue
            fi

            if [ -L "${dir}/etc/mcp-enabled/$filename" ]; then
              continue
            fi

            ln -sv "$json_file" "${dir}/etc/mcp-enabled/$filename"
          done
          echo combining config
          jq -s 'reduce .[] as $item ({}; . * $item)' etc/base.json etc/mcp-enabled/*json > etc/opencode.json
      - name: install.sh
        content: |
          ln -sfv $(pwd)/packages/opencode/dist/opencode-linux-x64/bin/opencode $GLOBAL_BINS_DIR/
      # TODO: compfuzor helpers for installing content, automate this below
      - name: install-user.sh
        basedir: False
        content: |
          dir={{DIR}}
          mkdir -p ~/.local/share/opencode/log

          [ -n "$TARGET" ] || TARGET="$HOME/.config/opencode"
          mkdir -p $(dirname $TARGET)
          ln -sv ${dir}/etc $TARGET/

          shopt -s nullglob
          for file in ${dir}/etc/mcp-enabled/*.json; do
            ln -sfv "$file" "$TARGET/mcp/"
          done
      - name: opencode-live
        basedir: False
        global: True
        content: |
          # note/beware that we also are pulling in env.exports
          exec bun run --cwd $DIR dev $(pwd)
  tasks:
    - import_tasks: tasks/compfuzor.includes
