---
- hosts: all
  vars:
    TYPE: playwright-mcp
    INSTANCE: git
    REPO: https://github.com/microsoft/playwright-mcp
    MCP_COMMAND:
      - mcp-server-playwright
    ENV:
      mcp_arg_allowed_hosts: ""
      mcp_arg_allowed_origins: ""
      mcp_arg_block_service_workers: ""
      mcp_arg_blocked_origins: ""
      mcp_arg_browser: "dev"
      mcp_arg_caps: ""
      mcp_arg_cdp_endpoint: ""
      mcp_arg_cdp_header: ""
      mcp_arg_console_level: "info"
      mcp_arg_device: ""
      mcp_arg_executable_path: ""
      mcp_arg_extension: ""
      mcp_arg_grant_permissions: ""
      mcp_arg_headless: ""
      mcp_arg_host: "localhost"
      mcp_arg_ignore_https_errors: ""
      mcp_arg_image_responses: ""
      mcp_arg_init_page: ""
      mcp_arg_init_script: ""
      mcp_arg_isolated: ""
      mcp_arg_no_sandbox: "true"
      mcp_arg_output_dir: "${DIR}/var/output"
      mcp_arg_port: ""
      mcp_arg_proxy_bypass: ""
      mcp_arg_proxy_server: ""
      mcp_arg_save_session: "true"
      mcp_arg_save_trace: "true"
      #mcp_arg_save_video: "800x600"
      mcp_arg_save_video: ""
      mcp_arg_secrets: ""
      mcp_arg_shared_browser_context: "true"
      mcp_arg_snapshot_mode: "incremental"
      mcp_arg_storage_state: "${DIR}/var/isolated-storage"
      mcp_arg_test_id_attribute: ""
      mcp_arg_timeout_action: "5000"
      mcp_arg_timeout_navigation: "60000"
      mcp_arg_user_agent: ""
      mcp_arg_user_data_dir: "${DIR}/var/profile"
      mcp_arg_viewport_size: "1024x1356"
    VAR_DIRS:
      - profile
      - output
      - isolated-storage
    LOG_DIR: True
    BINS:
      - name: install.sh
        content: |
          pnpm i
          pnpm link -g
  tasks:
    - import_tasks: tasks/compfuzor.includes
