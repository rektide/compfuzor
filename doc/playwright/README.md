---
type: Guide
title: Playwright browser automation and live Firefox boundaries
description: Return point for Compfuzor's Playwright MCP and CLI deployments, OpenCode V2 registration, verified separate-profile Firefox control, and the unsupported live Firefox attachment goal.
resource: /doc/playwright/README.md
status: active
generated: {by: 'model:openai/gpt-6.1-sol#high', at: 2026-10-18}
sources:
  - resource: opencode://ses_eaf8225bdffePtIv2dlUZgAGb3
    title: brave-sailor — commissioned Firefox investigation, refreshed archives/tools, repaired native configuration and CONFIG integration, verified OpenCode browser control
  - resource: /design/playwright/live-firefox0.glm53m.md
    title: Independent GLM safety/support investigation with revision-bound upstream source references
  - resource: https://github.com/microsoft/playwright-mcp/blob/b8b4183e099f/README.md
    title: MCP configuration, persistent profiles, CLI comparison, and extension limitations
  - resource: https://github.com/microsoft/playwright-cli/blob/main/README.md
    title: CLI sessions, browser installation, tab commands, and attachment modes; archive read at version 0.1.22
  - resource: https://opencode.ai/v2/docs/mcp-servers
    title: Native mcp.servers configuration, global CLI registration, environment maps, and management
  - resource: https://opencode.ai/v2/docs/migrate-v1
    title: V1 compatibility versus native V2 MCP shape
verification: Separate Playwright Firefox tested through MCP SDK, CLI, and the live OpenCode MCP connection; no attachment, inspection, copying, or modification of the desktop Firefox profile. Native Firefox BiDi channels and thousand-tab behavior were source-reviewed, not benchmarked here.
---

# Playwright: Firefox, MCP, and CLI

**Playwright supports Firefox; it is not Chrome/Edge-only. But it cannot attach
to an ordinarily running Firefox session.** The Chrome/Edge-only feature is
the extension bridge into an existing personal browser.

This is the maintained return point for
[`playwright-mcp.src.pb`](/playwright-mcp.src.pb) and
[`playwright-cli.opt.pb`](/playwright-cli.opt.pb).
The independent [live-Firefox assessment](/design/playwright/live-firefox0.glm53m.md)
holds detailed source evidence and alternatives; it is inquiry, not authorization
to reconfigure the personal browser.

## What the two playbooks provide

| | MCP source playbook | CLI package playbook |
|---|---|---|
| Installed interface | `@playwright/mcp`, stdio tools for OpenCode | `playwright-cli` from `@playwright/cli@latest` |
| Current verified version | 0.0.83 | 0.1.22 |
| Deployment | `/usr/local/src/playwright-mcp-git` | `/opt/playwright-cli-main` |
| Invocation | `node …/repo/cli.js --config …/playwright.json` | Shell commands with named `-s=` sessions |
| State | Separate persistent Firefox profile; headed | In-memory profile and headless by default; `--persistent` / `--headed` opt in |
| Agent workflow | Browser tools exposed through OpenCode Code Mode | Agent invokes CLI; optional upstream skills, not installed automatically |
| Personal Firefox attachment | Unsupported | Unsupported; `attach` is not generic Firefox attachment |

Both can open tabs, navigate, click/type, evaluate JavaScript, inspect page
structure, and take screenshots. Neither gains access to your personal Firefox
cookies, extensions, or tabs merely because it uses Firefox.

## The live thousand-tab Firefox goal

There are two distinct jobs:

1. **Open a tab in the existing Firefox:** `firefox -new-tab URL` normally
   forwards a command to the running instance. No automation setup is needed,
   but it does **not** give the agent control of that tab.
2. **Open and control a tab:** the installed Playwright tools can do this in
   their own Firefox session. They cannot do it inside your existing Firefox.

Do **not** substitute the personal profile path into `userDataDir`, or point
`executablePath` at `/usr/bin/firefox` expecting attachment. Launching against a
profile is different from attaching: Firefox locks the profile, and automation
launches can write preferences even before a usable session is established.
Default `firefox` uses Playwright's patched Firefox/Juggler build. Newer upstream
also has native Firefox `moz-*` BiDi launch channels; those are still launch-only,
not a bridge into a running desktop session. Our installation uses the patched,
tested path rather than the source-only native-channel option.

If actual-profile control remains essential, the next choice is a Firefox-native
extension bridge, or a deliberate Firefox restart with remote debugging plus a
**non-Playwright** BiDi client. Neither has been installed or enabled. Remote
debugging exposes a powerful local control endpoint and can change automation
preferences. See the assessment's [alternatives](/design/playwright/live-firefox0.glm53m.md#g-recommended-paths-least-invasive-first).

### Is this absurd or unsafe?

Separate-profile Playwright is a normal, practical setup. We added no custom
safety proxy, tab filters, permission gates, or browser extension.

For a hypothetical live-session connection, the important risks are:

- **Account authority:** automation can act with any logged-in account's
  permissions, including submitting forms and changing data. Page content can
  also contain misleading instructions to an agent.
- **Tab/session scope:** navigation and close commands can affect the wrong
  selected tab. Closing a launch-owned persistent context closes its browser;
  a persistent profile does not promise restoration of all open tabs.
- **Bulk listing is not necessarily passive metadata:** Playwright's tab
  headers fetch page titles and console/error information per page. This scales
  with tab count and produces a large result. No thousand-tab timing or
  discarded-tab-waking claim was verified here. Our tools cannot enumerate your
  desktop Firefox tabs in the first place.
- **Artifacts:** snapshots, screenshots, logs, and saved state can contain
  private page data. Removing automatic session recording does not disable
  ordinary tool output files.

## MCP configuration and installation

The source playbook now emits native JSON rather than dozens of blank
`mcp_arg_*` declarations. It uses an absolute source entrypoint instead of the
obsolete `mcp-server-playwright` launcher or a global pnpm link.

| Artifact | Purpose |
|---|---|
| `etc/mcp.json` | Portable local MCP record: command and graphical-session environment |
| `etc/playwright.json` | Browser type, headed/headless setting, viewport, profile and output directories |
| `/var/lib/playwright-mcp-git/profile` | Dedicated automation profile, **not** the desktop profile |
| `/var/lib/playwright-mcp-git/output` | Browser-tool output |
| `bin/install.sh` | `npm ci` in the source checkout |
| `bin/install-browser.sh` | Download the matching configured Playwright browser; excluded from the install compositor |

Default knobs are `PLAYWRIGHT_BROWSER=firefox` and
`PLAYWRIGHT_HEADLESS=false`. Browser names here are `firefox`, `chromium`, or
`webkit`. Overrides are Ansible extra vars; changing browser type also requires
running `install-browser.sh` again. Install dependencies separately if Playwright
reports missing system libraries; the playbook does not automatically run a
privileged `--with-deps` installation.

```sh
ansible-playbook -i 'localhost,' -c local playwright-mcp.src.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True -e MODULES_BYPASS=True \
  -e SYSTEMD_THUNK_BYPASS=True -e BINS_RUN_BYPASS=True
/usr/local/src/playwright-mcp-git/bin/install.sh
/usr/local/src/playwright-mcp-git/bin/install-browser.sh
```

No forced `--no-sandbox`, session recording, HTTP listener, isolated-storage
input, or shared-browser-context option is declared. This retains upstream
defaults rather than claiming a security sandbox. The MCP record captures only
`DISPLAY`, `WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR`, and `XAUTHORITY` when present:
the OpenCode background service did not inherit `DISPLAY` in the live test.
Rerender from the graphical session if those coordinates change. CLI calls from
a graphical shell normally already inherit them.

One profile cannot be opened by multiple browser processes simultaneously.
Concurrent MCP processes/projects should use distinct deployments/profiles;
shared HTTP context mode was not a solution to that lock and is no longer set.

## OpenCode V2 and Compfuzor CONFIG

OpenCode's native shape is `mcp.servers.playwright`, with `disabled: true` to
prevent connection. Compfuzor's existing portable consumer already had this
placement; no blanket V1 configuration migration was needed.

```sh
/usr/local/src/opencode-git/bin/config-remote.mjs put mcp-portable \
  /usr/local/src/playwright-mcp-git/etc/mcp.json playwright.json
```

This assembles `/etc/opt/opencode-git/opencode.json`. **On this host that is not
the same file as `~/.config/opencode/opencode.json`.** The live user config was
also registered through `opencode mcp add playwright --global`, passing the
command and display environment from the portable record, preserving unrelated
entries and the old disabled `playwright-mcp` entries.

The running server initially retained its old MCP set. Its own OpenAPI contract
provided a non-restarting activation path, used successfully here:

```sh
opencode api put \
  '/api/experimental/mcp/playwright?location[directory]=/home/rektide/src/compfuzor' \
  --data "$(jq -c '{config: .}' /usr/local/src/playwright-mcp-git/etc/mcp.json)"
opencode mcp list
```

The runtime addition is location-scoped and transient; the global registration
is the persistent part. `playwright` reported **connected**, and actual tools
were then available in this session. No OpenCode service restart was performed.

**CONFIG repair:** JSON assembly now loads a declared producer environment only
when the record contains `${VAR}` placeholders. Literal records (including
native `{env:VAR}` references) no longer require an unrelated `env.export`.
Variable-bearing records still fail for missing/broken declared env files or
unresolved variables. The older relative-env assumption is **not** repaired for
all split-ETC variable-bearing producers; this native record does not use it.
The processor correction was deployed narrowly to
`/usr/local/src/opencode-git/bin/config/processor.sh`, without rerendering the
whole OpenCode service deployment.

See [consumer configuration](/doc/config/consumer-toolkit.md) for the generic
assembly/remote-input lifecycle and [the CONFIG map](/doc/config/README.md) for
the rebuilt subsystem's maintained home.

## Returning through the CLI

```sh
ansible-playbook -i 'localhost,' -c local playwright-cli.opt.pb \
  -e PKGS_BYPASS=True -e APT_BYPASS=True -e SYSTEMD_THUNK_BYPASS=True
playwright-cli install-browser firefox
playwright-cli -s=work open about:blank --browser=firefox --headed --persistent
playwright-cli -s=work tab-new https://example.com
playwright-cli -s=work tab-list
playwright-cli -s=work snapshot
playwright-cli -s=work close
```

Use `tab-new`, not `goto`, when you want another tab. `goto` navigates the
selected tab. `list` lists automation sessions; `tab-list` lists tabs within
one session. Avoid broad `close-all`, `kill-all`, and `delete-data` unless that
is actually the intended operation. No optional skill registration is necessary
for skills-less CLI use; `playwright-cli --help` is the command reference.

## Verification and update evidence — 2026-10-18

- `dl` refreshed the Playwright, playwright-mcp, and playwright-cli archives.
  It returned nonzero for an externally changed archlist export and unavailable
  GitHub wiki clones; repository fetches completed. The archlist was not adopted
  or overwritten to hide that diagnostic.
- Actual playbooks rendered locally with repository/package/bin-execution
  bypasses; generated installers were then run explicitly. CLI upgraded from
  0.1.13 to 0.1.22. MCP source dependencies and Firefox build 1553 were installed.
  Upstream's browser installer also garbage-collected old unused Chromium 1223
  cache builds; no Compfuzor cleanup policy was added.
- `npm audit --omit=dev --json`: zero reported production vulnerabilities.
  Full dependency installation reported three development vulnerabilities
  (one low, two moderate); no automatic audit fixes were applied.
- Both playbook syntax checks, `tests/integration/playwright.test.py`,
  `mcp_records.test.py`, `config_remote.test.py`, and `config_graph.test.py`
  passed, as did the OpenCode playbook syntax check and CONFIG transaction-fault
  and reusable-context suites. The graph regression covers literal records without producer env,
  strict expansion failures, and preservation of prior assembled output.
- Disposable headless MCP and CLI Firefox sessions each opened/listed two data
  tabs, evaluated `21 * 2`, and closed their own browser. Scratch evidence:
  `.test-agent/playwright/smoke-1792352153490/results.json` (local, ignored).
- Live OpenCode MCP opened a visible dedicated Firefox with a demonstration
  tab titled **OpenCode Playwright Firefox** and successfully read its heading
  and evaluated JavaScript. That browser was left open for the operator.
  The personal Firefox, its profile, and its existing tabs were not inspected
  or controlled.
