---
- hosts: all
  vars:
    TYPE: context7
    INSTANCE: git
    REPO: https://github.com/upstash/context7
    ETC_DIRS:
      - mcp
    ETC_FILES:
      - name: mcp/opencode-context7.json.envsubst
        json:
          mcp:
            context7:
              enabled: true
              type: "remote"
              url: "https://context7.liam.sh/mcp"
              headers:
                Authorization: "Bearer ${CONTEXT7_API_KEY}"
    BINS:
      - name: install.sh
        content: |
          npm install -g
      - name: install-opencode.sh
        basedir: False
        env: False
        content: |
          shopt -s nullglob
          for file in {{DIR}}/etc/mcp/*.json.envsubst
          do
            echo "Processing $file"
            cat "$file" | envsubst > "etc/mcp/$(basename "$file" .envsubst)"
          done
          for file in {{DIR}}/etc/mcp/*.json
          do
            ln -sfv "$file" etc/mcp/
          done
          [ -e 'bin/config.sh' ] && ./bin/config.sh
    #ENV:
    #  CONTEXT7_API_KEY: ""
  tasks:
    - import_tasks: tasks/compfuzor.includes
