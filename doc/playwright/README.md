---
type: Guide
title: Playwright browser automation, Firefox and branded-Chrome boundaries
description: Return point for Compfuzor's Playwright MCP and CLI deployments, OpenCode V2 registration, verified separate-profile Firefox control, the branded-Chrome Google-SSO variant, and the unsupported live Firefox attachment goal.
resource: /doc/playwright/README.md
status: active
generated: {by: 'model:openai/gpt-6.1-sol#high', at: 2026-10-18}
sources:
  - resource: opencode://ses_eaf8225bdffePtIv2dlUZgAGb3
    title: brave-sailor — commissioned Firefox investigation, refreshed archives/tools, repaired native configuration and CONFIG integration, verified OpenCode browser control; commissioned branded-Chrome Google-SSO variant after the masked Firefox build still failed Google's email step
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

# Playwright: Firefox, branded Chrome, MCP, and CLI

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
| `etc/automation-masking.js` | Init script reporting the regular-browser `navigator.webdriver` value |
| `/var/lib/playwright-mcp-git/profile` | Dedicated automation profile, **not** the desktop profile |
| `/var/lib/playwright-mcp-git/output` | Browser-tool output |
| `etc/playwright-chrome.json` | Branded-Chrome variant: `channel: chrome`, headful, same viewport, own profile and output |
| `etc/mcp-chrome.json` | Portable local MCP record for the branded-Chrome server, same environment map |
| `/var/lib/playwright-mcp-git/profile-chrome` | Dedicated branded-Chrome automation profile |
| `/var/lib/playwright-mcp-git/output-chrome` | Branded-Chrome server tool output |
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

### Automation markers

The patched Firefox build hardwires `navigator.webdriver: true`, and Google
sign-in (used by OpenAI SSO) blanket-rejects `webdriver:true` browsers even
for headed, human-driven sessions — the linked support page names "controlled
through software automation" as a block reason. The user agent and other
navigator surfaces already match the regular build.
`files/playwright-mcp/automation-masking.js` (rendered from a name-only ETC
entry) is registered through `browser.initScript` and runs before any page
script. It reports the spec-default regular-browser value for
`navigator.webdriver` (`false`) and restores the stock PDF-viewer surface the
patched build omits (5 Chrome-compat `plugins` entries, 2 `mimeTypes`,
`pdfViewerEnabled: true`). It is also a **tripwire**: every read (including
`typeof`), `Object.getOwnPropertyDescriptor(s)` probe, and
`Function.prototype.toString` native-check of the masked surface fires a
`console.warn` naming the probe kind, key, and caller stack site — visible
through the MCP console tooling — while the getters and wrapped builtins
still answer native-shaped `toString()` so the instrumentation does not
become its own tell. `'webdriver' in navigator`-style probes do not invoke
getters and remain unobservable without a navigator Proxy (a larger
fingerprint seam than the signal). Upstream Playwright MCP does the
Chromium equivalent by
default (`--disable-blink-features=AutomationControlled`), so this brings the
Firefox profile to parity rather than adding a novel deception. A config-file
change is only read at server startup: an unchanged MCP command needs an
explicit `mcp … disconnect`/`connect` cycle (or OpenCode restart) before the
new config takes effect.

**That masking was necessary but not sufficient.** Verified live with
`webdriver: false` and the regular Firefox UA, Google sign-in (OpenAI SSO)
still rejected the account at the email step (`/v3/signin/rejected`): the
patched Juggler build carries deeper fingerprints — `navigator.plugins.length`
is 0 where a regular Firefox reports 5 compatibility entries, and likely other
build tells — so no in-page masking clears Google's browser check. **Branded
Chrome is the Google-SSO-capable path.** `etc/playwright-chrome.json` and
`etc/mcp-chrome.json` deploy a second, separate headful server
(`launchOptions.channel: chrome`, google-chrome 150, own `profile-chrome`);
it passed the email step to the password prompt in the live test. The
operator then completed password + 2FA in the visible Chrome window once:
the Google and OpenAI/ChatGPT sessions both landed in the persistent
`profile-chrome` and survived a full browser relaunch headed **and** fully
headless with no re-authentication. Headless needs one addition: Chrome
stamps `HeadlessChrome` into its user agent and Cloudflare's "Just a
moment…" gate stops it, so headless launches must pass a regular
`userAgent` override
(`Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36`);
with that, headless loads straight into the logged-in ChatGPT UI. No masking
init script is registered for Chrome — upstream already handles Chromium
automation markers. Register it under its own server name with the same
display environment as the Firefox record:

```sh
opencode mcp add playwright-chrome --global \
  --env DISPLAY=:0 --env WAYLAND_DISPLAY=wayland-0 \
  --env XAUTHORITY=$HOME/.Xauthority --env XDG_RUNTIME_DIR=/run/user/1000 -- \
  node /usr/local/src/playwright-mcp-git/repo/cli.js \
  --config /etc/opt/playwright-mcp-git/playwright-chrome.json
```

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
- 2026-10-18 (later): Google rejected OpenAI SSO in the automation Firefox
  (`navigator.webdriver: true` was the tell; the UA was already regular). The
  masking init script was deployed and verified live after an explicit server
  disconnect/connect cycle: `webdriver: false`, regular Firefox 156 UA, and
  Google's sign-in page rendering without the "This browser or app may not be
  secure" block. Completion of the actual login is the operator's step.
- 2026-10-18 (dump lead, closed): source analysis suggested `window.dump` as
  a surviving tell (Playwright's user.js and the remote agent's recommended
  prefs both enable it; official Firefox defaults the pref off). Chased to
  ground and disproven on this machine: Debian's stock Firefox 157 exposes
  the binding regardless — with `browser.dom.window.dump.enabled=false`
  confirmed in the live session's `prefs.js`, `typeof window.dump` is still
  `"function"` (the pref only gates whether `dump()` prints; the binding
  ships unconditionally in 157). `remote.prefs.recommended=false` and the
  pref restore changed nothing observable, and the email step stayed
  rejected in every configuration. Final standing verdict:
  [remote-agent-detect0](/design/playwright/remote-agent-detect0.glm53m.md)
  — under BiDi/WebDriver, automation-active state is live engine state with
  no page-reachable channel, and Google's rejection survives every
  page/JS/header/pref/typing normalization we could apply. Automated Google
  sign-in on Firefox is effectively unreachable from our layers; branded
  Chrome (CDP, no engine flag) is the supported path, and Firefox remains
  usable for everything else including an established (manually created)
  Google session. Disk note: the 11.4 GB gecko-dev clone pushed this
  already-full volume to 100% and the archive was removed mid-analysis;
  citations reference reads completed before removal.
- 2026-10-18 (post-mortem): two further "obvious indicator" hypotheses were
  tested and exonerated. Wire headers: the patched build's navigation headers
  are shape-identical to stock Firefox 157 (`Accept-Language: en-US,en;q=0.9`
  is current-normal, verified against the stock binary; full Sec-Fetch
  family, Priority, zstd all match). Automation prefs: Playwright's BiDi
  profile inherits a Puppeteer-derived pref set that disables the popup
  blocker, ETP, Safe Browsing, and HTTPS-First (page-observable markers);
  launching stock Firefox with all of those restored to stock values was
  still rejected at the email step. Remaining standing explanation: the
  engine-level automation-active state of a BiDi/Juggler session itself,
  which no page, header, or pref layer can mask — consistent with branded
  Chrome under CDP passing, since CDP attach does not set a webdriver flag
  anywhere in the engine.
- 2026-10-18 (final): the operator completed password + 2FA once in the
  branded-Chrome window; the Google and ChatGPT sessions persisted in
  `profile-chrome` across a full browser relaunch headed **and** fully
  headless (headless needs a regular `userAgent` override — Chrome stamps
  `HeadlessChrome` into its UA and Cloudflare's gate stops that). The v3
  instrumented masking (`files/playwright-mcp/automation-masking.js`) was
  verified live: surface regular, and read/`typeof`/descriptor/native-check
  probes each fired a caller-identifying console warning. An unexplained
  Chromium-layout store was found clobbering the Firefox `profile` dir (no
  valuable state); it was moved aside as
  `var/profile.clobbered-chromium` and the directory recreated clean.
- 2026-10-18 (later still): With masking verified live, Google still rejected
  the submitted email in the automation Firefox (`/v3/signin/rejected`):
  fingerprint tells beyond webdriver — the patched build reports
  `navigator.plugins.length` 0 where a regular Firefox reports 5 compatibility
  entries, among other build-tell differences. A real branded-Chrome test
  (playwright-cli `--browser=chrome`, headed, separate `profile-chrome`)
  passed the email step to the password prompt and was stopped there — no
  credentials beyond the test email were entered. The branded-Chrome MCP
  variant (`etc/playwright-chrome.json`, `etc/mcp-chrome.json`,
  `profile-chrome`, `output-chrome`) was rendered, the playbook and
  integration test extended, and the server registered globally plus
  activated at runtime without restarting OpenCode (`opencode mcp list`:
  **connected**); a non-Google smoke test through the MCP confirmed a
  Chrome/150 UA, native `webdriver: false`, and snapshots landing in the
  configured `output-chrome`. During the first render a string-typed
  `MCP_ENV` extra var (`-e 'MCP_ENV=…'` instead of a JSON blob) corrupted the
  Firefox record's environment map; the corrected rerender reproduced
  `etc/mcp.json` byte-identical to its prior checksum.
