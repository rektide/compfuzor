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
      - mcp-disabled
      - agent
    ETC_FILES:
      - name: base.json
        json:
          "$schema": "https://opencode.ai/config.json"
      - name: agent/mcp-gathering.md
        content: |
          ---
          description: Tool and documentation gathering, review, and comparison
          mode: fork
          ---

          You are looking to find both the best documentation, and, crucially, you want to understand and explain the strengths and weaknesses of what each tool gives you, comparing against one another. Follow these steps:

          1. Identify and list which MCP tools might be best for doing research on the libraries or problem we need to work with next. For example, rustdocs, cratedocs, LSP, context7 are all well known MCPs for finding information on code and libraries.
          2. After listing tools you want to try, work with each of those tool, one after another, trying to find relevant documentation for the context.
          3. After looping through all tools, you will have seen more of the total documentation available. This might suggest other research and exploration you could do. Do a second pass. You don't have to, but if you think there might be a benefit, try new queries that you think could be useful for each tool.
          4. Compare how the different sources do. Which sources do you think are the most pertinent? Which have the best examples? Which have are the most comprehensive? Which feel the most on target? How would you characterize the help you got from each tool, when trying to do research about this library or topic?
          5. Outline what you have learned.
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
          dir={{DIR}}
          mkdir -p ${dir}/etc/mcp-disabled

          shopt -s nullglob
          configs=(${dir}/etc/mcp/*.json)
          disabled=(${dir}/etc/mcp-disabled/*.json)

          jq -s 'reduce .[] as $item ({}; . * $item)' ${dir}/etc/base.json "${configs[@]}" "${disabled[@]}" > ${dir}/etc/opencode.json
      - name: disable.sh
        content: |
          shopt -s nullglob
          dir={{DIR}}
          mkdir -p ${dir}/etc/mcp-disabled

          files=()
          for pattern in "$@"; do
            if [ -f "$pattern" ]; then
              files+=("$pattern")
              continue
            fi

            orig_pattern="$pattern"
            start_count=${#files[@]}

            pattern="${pattern%.json}"
            for json_file in ${dir}/etc/mcp/*.json; do
              filename=$(basename "$json_file")
              [[ "$filename" =~ $pattern ]] && files+=("$json_file") && continue
              [[ "${filename%.json}" =~ $pattern ]] && files+=("$json_file")
            done

            [ $start_count -eq ${#files[@]} ] && echo "no match: $orig_pattern"
          done

          for json_file in "${files[@]}"; do
            filename=$(basename "$json_file")
            target="${dir}/etc/mcp-disabled/$filename"

            if [ -f "$target" ]; then
              echo "skipped: $filename"
              continue
            fi

            mcp_key=$(jq -r '.mcp | keys[0]' "$json_file")
            echo "{\"mcp\":{\"$mcp_key\":{\"enabled\":false}}}" > "$target"
            echo "created: $filename"
          done
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
      - name: opencode-live
        basedir: False
        global: True
        content: |
          # note/beware that we also are pulling in env.exports
          exec bun run --cwd $DIR dev $(pwd)
  tasks:
    - import_tasks: tasks/compfuzor.includes
