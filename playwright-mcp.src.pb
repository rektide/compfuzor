---
- hosts: all
  vars:
    TYPE: playwright-mcp
    INSTANCE: git
    REPO: https://github.com/microsoft/playwright-mcp
    ENV:
      opencode_mcp_file: "${DIR}/etc/mcp/opencode-playwright-mcp.json"
      #env2mcp_prefix: playwright_mcp
      mcp_name: "{{TYPE|regex_replace('-mcp$', '')}}"
      playwright_mcp_allowed_hosts: ""
      playwright_mcp_allowed_origins: ""
      playwright_mcp_block_service_workers: ""
      playwright_mcp_blocked_origins: ""
      playwright_mcp_browser: "dev"
      playwright_mcp_caps: ""
      playwright_mcp_cdp_endpoint: ""
      playwright_mcp_cdp_header: ""
      playwright_mcp_console_level: "info"
      playwright_mcp_device: ""
      playwright_mcp_executable_path: ""
      playwright_mcp_extension: ""
      playwright_mcp_grant_permissions: ""
      playwright_mcp_headless: ""
      playwright_mcp_host: "localhost"
      playwright_mcp_ignore_https_errors: ""
      playwright_mcp_image_responses: ""
      playwright_mcp_init_page: ""
      playwright_mcp_init_script: ""
      playwright_mcp_isolated: ""
      playwright_mcp_no_sandbox: "true"
      playwright_mcp_output_dir: "${DIR}/var/output"
      playwright_mcp_port: ""
      playwright_mcp_proxy_bypass: ""
      playwright_mcp_proxy_server: ""
      playwright_mcp_save_session: "true"
      playwright_mcp_save_trace: "true"
      #playwright_mcp_save_video: "800x600"
      playwright_mcp_save_video: ""
      playwright_mcp_secrets: ""
      playwright_mcp_shared_browser_context: "true"
      playwright_mcp_snapshot_mode: "incremental"
      playwright_mcp_storage_state: "${DIR}/var/isolated-storage"
      playwright_mcp_test_id_attribute: ""
      playwright_mcp_timeout_action: "5000"
      playwright_mcp_timeout_navigation: "60000"
      playwright_mcp_user_agent: ""
      playwright_mcp_user_data_dir: "${DIR}/var/profile"
      playwright_mcp_viewport_size: "1024x1356"
    ETC_DIRS:
      - mcp
    VAR_DIRS:
      - profile
      - output
      - isolated-storage
    LOG_DIR: True
    BINS:
      - src: ../env2mcp
        raw: True
      - name: install.sh
        content: |
          pnpm i
          pnpm link -g
      - name: config.sh
        content: |
          echo generating mcp from template
          $DIR/bin/env2mcp \
            --set-json mcp.${MCP_NAME}.command='["mcp-server-playwright"]' \
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
