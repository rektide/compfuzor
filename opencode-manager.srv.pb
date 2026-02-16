---
- hosts: all
  vars:
    TYPE: opencode-manager
    INSTANCE: git
    src: "{{SRCS_DIR}}/opencode-manager-git"
    
    # Directories
    VAR_DIR: True
    VAR_DIRS:
      - data
      - workspace
    
    # Symlink required files from src to srv instance so we can run from there
    # This keeps CWD in the srv instance without modifying src
    LINKS:
      # Data directories
      - src: "{{VAR}}/data"
        dest: "{{DIR}}/data"
      - src: "{{VAR}}/workspace"
        dest: "{{DIR}}/workspace"
      # Code and dependencies - read-only links to src
      - src: "{{src}}/backend"
        dest: "{{DIR}}/backend"
      - src: "{{src}}/node_modules"
        dest: "{{DIR}}/node_modules"
      - src: "{{src}}/shared"
        dest: "{{DIR}}/shared"
      - src: "{{src}}/package.json"
        dest: "{{DIR}}/package.json"
      - src: "{{src}}/pnpm-workspace.yaml"
        dest: "{{DIR}}/pnpm-workspace.yaml"
    
    # Service configuration
    port: "5001"
    opencodePort: "5551"
    host: "0.0.0.0"
    nodeEnv: "production"
    logLevel: "debug"
    
    # File limits
    maxFileSize: "50"
    maxUploadSize: "50"
    
    # Timeouts (milliseconds)
    processStartWait: "3000"
    processVerifyWait: "1000"
    healthCheckInterval: "5000"
    healthCheckTimeout: "20000"
    
    # Passkey/WebAuthn
    passkeyRpId: "localhost"
    passkeyRpName: "OpenCode Manager"
    passkeyOrigin: "http://localhost:5003"
    
    # Environment variables
    ENV:
      PORT: "{{port}}"
      HOST: "{{host}}"
      CORS_ORIGIN: "http://localhost:5173"
      NODE_ENV: "{{nodeEnv}}"
      LOG_LEVEL: "{{logLevel}}"
      OPENCODE_SERVER_PORT: "{{opencodePort}}"
      OPENCODE_HOST: "127.0.0.1"
      DATABASE_PATH: "./data/opencode.db"
      WORKSPACE_PATH: "./workspace"
      PROCESS_START_WAIT_MS: "{{processStartWait}}"
      PROCESS_VERIFY_WAIT_MS: "{{processVerifyWait}}"
      HEALTH_CHECK_INTERVAL_MS: "{{healthCheckInterval}}"
      HEALTH_CHECK_TIMEOUT_MS: "{{healthCheckTimeout}}"
      MAX_FILE_SIZE_MB: "{{maxFileSize}}"
      MAX_UPLOAD_SIZE_MB: "{{maxUploadSize}}"
      DEBUG: "false"
      PASSKEY_RP_ID: "{{passkeyRpId}}"
      PASSKEY_RP_NAME: "{{passkeyRpName}}"
      PASSKEY_ORIGIN: "{{passkeyOrigin}}"
    
    # Systemd service - runs from srv instance directory, not src
    SYSTEMD_SERVICE: True
    SYSTEMD_CWD: "{{DIR}}"
    SYSTEMD_EXEC: "bun backend/src/index.ts"
    
  tasks:
    - include: tasks/compfuzor.includes type=srv
