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
    # OpenCode's background service need not inherit the graphical session.
    # Pass only display connection coordinates captured by this local render.
    MCP_ENV: >-
      {{ ansible_env | dict2items |
         selectattr('key', 'in', ['DISPLAY', 'WAYLAND_DISPLAY', 'XDG_RUNTIME_DIR', 'XAUTHORITY']) |
         items2dict }}
    # Native JSON avoids shell expansion and --boolean=true flag synthesis.
    # No sandbox override, automatic recording, HTTP listener, or profile sharing.
    ETC_FILES:
      # Evaluated in every page before page scripts. The patched Juggler build
      # hardwires navigator.webdriver=true; regular browsers report false, and
      # Google sign-in (e.g. OpenAI SSO) blanket-rejects webdriver:true even
      # for headed human-driven sessions. The user agent and other navigator
      # surfaces already match the regular build; this normalizes the one
      # automation tell. Bash-style ${} expansion and Jinja {{}} must stay out.
      - name: automation-masking.js
        content: |
          try {
            Object.defineProperty(Navigator.prototype, 'webdriver', {
              get: function () { return false; },
              enumerable: true,
              configurable: true,
            });
          } catch (error) {}
      - name: playwright.json
        json:
          browser:
            browserName: "{{PLAYWRIGHT_BROWSER}}"
            userDataDir: "{{VAR}}/profile"
            initScript:
              - "{{ETC}}/automation-masking.js"
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
      `etc/automation-masking.js` reports the regular-browser value for
      navigator.webdriver so Google SSO (OpenAI login) accepts the profile;
      the user agent and other markers already match the regular build.
      The MCP record carries the rendering session's display coordinates so
      headed Firefox also works from a background OpenCode service. Rerender
      from the graphical session if its display/socket paths change.

      OpenCode V2 imports portable records under `mcp.servers`, for example:

          /usr/local/src/opencode-git/bin/config-remote.mjs put mcp-portable \
            {{ETC}}/mcp.json playwright.json

      See compfuzor's `doc/playwright/README.md` for the CLI/MCP distinction,
      live Firefox limitations, usage, and verification evidence.
  tasks:
    - import_tasks: tasks/compfuzor.includes
