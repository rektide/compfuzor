---
- hosts: all
  vars:
    TYPE: playwright-mcp
    INSTANCE: git
    REPO: https://github.com/microsoft/playwright-mcp
    # Playwright's own Firefox, NOT the running desktop Firefox/profile.
    # browserName accepts chromium, firefox, or webkit.
    PLAYWRIGHT_BROWSER: firefox
    PLAYWRIGHT_HEADLESS: false
    MCP_COMMAND:
      - node
      - "{{REPO_DIR}}/cli.js"
      - --config
      - "{{ETC}}/playwright.json"
    # Native JSON avoids shell expansion and --boolean=true flag synthesis.
    # No sandbox override, automatic recording, HTTP listener, or profile sharing.
    ETC_FILES:
      - name: playwright.json
        json:
          browser:
            browserName: "{{PLAYWRIGHT_BROWSER}}"
            userDataDir: "{{VAR}}/profile"
            launchOptions:
              headless: "{{PLAYWRIGHT_HEADLESS | bool}}"
            contextOptions:
              viewport: {width: 1356, height: 1356}
          outputDir: "{{VAR}}/output"
    VAR_DIRS:
      - profile
      - output
    BINS:
      - name: install.sh
        basedir: "{{REPO_DIR}}"
        content: |
          npm ci
      - name: install-browser.sh
        compose: false
        basedir: "{{REPO_DIR}}"
        content: |
          node cli.js install-browser {{ PLAYWRIGHT_BROWSER | quote }} "$@"
    README: |
      # Playwright MCP

      `bin/install.sh` installs the checked-out server dependencies;
      `bin/install-browser.sh` downloads the matching {{PLAYWRIGHT_BROWSER}}.
      `etc/mcp.json` is a portable stdio server record for CONFIG consumers.
      `etc/playwright.json` configures a separate persistent automation profile
      at `{{VAR}}/profile`, not the desktop browser profile. Launch is lazy.

      OpenCode V2 imports portable records under `mcp.servers`, for example:

          /usr/local/src/opencode-git/bin/config-remote.mjs put mcp-portable \
            {{ETC}}/mcp.json playwright.json

      See compfuzor's `doc/playwright/README.md` for the CLI/MCP distinction,
      live Firefox limitations, usage, and verification evidence.
  tasks:
    - import_tasks: tasks/compfuzor.includes
