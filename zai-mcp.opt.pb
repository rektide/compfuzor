---
- hosts: all
  vars:
    REPO_NPM: '@z_ai/mcp-server'
    ETC_DIRS:
      - mcp
    ETC_FILES:
      - name: mcp/opencode-zai-vision.json.envsubst
        json:
          mcp:
            z-vision:
              enabled: true
              type: "local"
              command: ["zai-mcp-server"]
              environment:
                Z_AI_API_KEY: "${Z_AI_API_KEY}"
                Z_AI_MODE: "ZAI"
      - name: mcp/opencode-zai-web-search.json.envsubst
        json:
          mcp:
            z-search:
              enabled: true
              type: "remote"
              url: "https://api.z.ai/api/mcp/web_search_prime/mcp"
              headers:
                Authorization: "Bearer ${Z_AI_API_KEY}"
      - name: mcp/opencode-zai-web-reader.json.envsubst
        json:
          mcp:
            z-reader:
              enabled: true
              type: "remote"
              url: "https://api.z.ai/api/mcp/web_reader/mcp"
              headers:
                Authorization: "Bearer ${Z_AI_API_KEY}"
      - name: mcp/opencode-zai-zread.json.envsubst
        json:
          mcp:
            z-read:
              enabled: true
              type: "remote"
              url: "https://api.z.ai/api/mcp/web_reader/mcp"
              headers:
                Authorization: "Bearer ${Z_AI_API_KEY}"
    BINS:
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
    #  Z_AI_API_KEY: ""
  tasks:
    - import_tasks: tasks/compfuzor.includes
