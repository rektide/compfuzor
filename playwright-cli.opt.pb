---
- hosts: all
  vars:
    NPM: '@playwright/cli@latest'
    README: |
      # Playwright CLI

      `bin/install.sh` installs/updates `playwright-cli` from @playwright/cli.
      This is shell-driven browser automation, not an MCP server. Use named
      sessions (`playwright-cli -s=work ...`) to return to the same browser.
      Profiles are in-memory by default; `open --persistent` saves one.

      For a separate Playwright Firefox (not the live desktop Firefox):

          playwright-cli install-browser firefox
          playwright-cli -s=work open about:blank --browser=firefox --headed --persistent
          playwright-cli -s=work tab-new https://example.com
          playwright-cli -s=work tab-list

      See compfuzor's `doc/playwright/README.md` for live browser limitations
      and OpenCode MCP setup. No skills or browser extensions are installed
      automatically; `playwright-cli --help` also supports skills-less use.
  tasks:
    - import_tasks: tasks/compfuzor.includes
