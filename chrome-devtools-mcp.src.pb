---
- hosts: all
  vars:
    TYPE: chrome-devtools-mcp
    INSTANCE: git
    REPO: https://github.com/ChromeDevTools/chrome-devtools-mcp
    MCP_COMMAND:
      - chrome-devtools-mcp
    ENV:
      mcp_arg_user_data_dir: "{{DIR}}/var/profile"
      mcp_arg_channel: "dev"
      mcp_arg_log_file: "{{LOG}}/chrome-devtoosls.log"
      mcp_arg_viewport: "1024x1356"
      mcp_arg_headless: "false"
      mcp_arg_isolated: "false"
      mcp_arg_auto_connect: "false"
      mcp_arg_category_emulation: "false"
      mcp_arg_category_performance: "true"
      mcp_arg_category_network: "true"
      mcp_arg_accept_insecure_certs: ""
      mcp_arg_chrome_args: ""
      mcp_arg_browser_url: ""
      mcp_arg_ws_endpoint: ""
      mcp_arg_ws_headers: ""
      mcp_arg_executable_path: ""
      mcp_arg_proxy_server: ""
    VAR_DIRS:
      - profile
    LOG_DIR: True
    BINS:
      - name: build.sh
        content: |
          # too fragile for pnpm
          npm ci
          npm run build
          npm install -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
