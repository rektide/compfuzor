---
- hosts: all
  vars:
    TYPE: chrome-devtools-mcp
    INSTANCE: git
    REPO: https://github.com/ChromeDevTools/chrome-devtools-mcp
    ENV:
      opencode_mcp_file: "{{DIR}}/etc/mcp/opencode-chrome-devtoosls.json"
      chrome_devtoosls_user_data_dir: "{{DIR}}/var/profile"
      chrome_devtoosls_channel: "dev"
      chrome_devtoosls_log_file: "{{LOG}}/chrome-devtoosls.log"
      chrome_devtoosls_viewport: "1024x1356"
      chrome_devtoosls_headless: "false"
      chrome_devtoosls_isolated: "false"
      chrome_devtoosls_auto_connect: "false"
      chrome_devtoosls_category_emulation: "false"
      chrome_devtoosls_category_performance: "true"
      chrome_devtoosls_category_network: "true"
      chrome_devtoosls_accept_insecure_certs: ""
      chrome_devtoosls_chrome_args: ""
      chrome_devtoosls_browser_url: ""
      chrome_devtoosls_ws_endpoint: ""
      chrome_devtoosls_ws_headers: ""
      chrome_devtoosls_executable_path: ""
      chrome_devtoosls_proxy_server: ""
    ETC_DIRS:
      - mcp
    VAR_DIRS:
      - profile
    LOG_DIR: True
    BINS:
      - src: ../env2mcp
        raw: True
      - name: build.sh
        content: |
          # too fragile for pnpm
          npm ci
          npm run build
          npm install -g
      - name: config.sh
        content: |
          echo generating mcp from template
          $DIR/bin/env2mcp \
            --set-json mcp.${MCP_NAME}.command='["chrome-devtools-mcp"]' \
            --set-json mcp.${MCP_NAME}.enabled=true \
            --set-json mcp.${MCP_NAME}.type=local \
            --set-json '$schema=https://opencode.ai/config.json' \
            > $OPENCODE_MCP_FILE
      - name: install-opencode.sh
        basedir: False
        env: False
        content: |
          # run from opencode directory
          $DIR/bin/config.sh
          echo
          echo installing
          (
            source $DIR/env;
            ln -sv $OPENCODE_MCP_FILE etc/mcp/
          )
          [ -e 'bin/config.sh' ] && ./bin/config.sh
  tasks:
    - import_tasks: tasks/compfuzor.includes
