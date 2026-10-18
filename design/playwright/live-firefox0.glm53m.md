---
type: Report
title: Playwright × live Firefox — can it orchestrate the actual running profile?
description: Source-grounded assessment of whether Playwright (playwright-core CLI tooling and @playwright/mcp) can attach to or safely drive an already-running native Firefox session with ~1000 tabs, covering attach surfaces, the moz-firefox BiDi channels, tab-listing side effects, teardown semantics, and recommended minimally-invasive paths.
resource: /design/playwright/live-firefox0.glm53m.md
status: draft
author: rektide (commission); model:glm-5.3#max (investigation and report)
generated:
  at: 2026-10-18
  by: model:glm-5.3#max
ticket: ""
tags: [playwright, firefox, webdriver-bidi, mcp, browser-automation, assessment]
sources:
  - resource: opencode://ses_eaf8225bdffePtIv2dlUZgAGb3
    title: Commissioning session — live ~1000-tab Firefox profile question, constraints, and scope
  - resource: opencode://ses_eaf816f55ffeVksaGbjo5Sm2TO
    title: Investigation session — archive source reading, upstream doc checks, disposable client-side probes, report, and correction round 1 (tab-listing cost precision, -new-tab profile-write claim, teardown scoping)
  - resource: /home/rektide/archive/microsoft/playwright
    title: microsoft/playwright @ b335271cdc2b (1.65.0-next, 2026-10-17); MCP server source now lives in-repo under packages/playwright-core/src/tools
  - resource: /home/rektide/archive/microsoft/playwright-mcp
    title: microsoft/playwright-mcp @ b8b4183e099f (0.0.83, 2026-10-08); thin CLI wrapper delegating to playwright-core
  - resource: https://firefox-source-docs.mozilla.org/remote/
    title: Firefox Remote Protocols docs (index, Prefs, Debugging) — BiDi-only state, startup flags, pref mutations
  - resource: https://wiki.mozilla.org/Firefox/CommandLineOptions
    title: Firefox command-line options (-new-tab, -no-remote remote-command semantics)
verification: >
  Claims cite file:line in the archived checkouts above. Client-side guards
  re-verified at runtime against published playwright-core 1.64.1 in a
  disposable /tmp/opencode scratch (no browser binary launched, no profile
  read or written, per commission constraints). Line numbers drift with
  upstream; re-grep the named symbols when in doubt.
---

# Playwright × live Firefox — can it orchestrate the actual running profile?

**Situation.** A daily-driver Firefox is already running with ~1000 tabs. The
desired capability: open/control a *new* tab in that live session, leaving the
other tabs alone, with minimal changes and no custom safeguards built. Question:
can Playwright — CLI (`playwright` / `playwright-core`, incl. the `playwright`
MCP tooling) or MCP server (`@playwright/mcp`) — do this? Assessment below is
supported-vs-unsupported, grounded in current source; it is not a safety
argument by default.

**Verdict in one line.** *Attach* to an already-running native Firefox is
**not supported by Playwright at any attach surface** (no CDP in Firefox, no
Playwright-protocol server in it, no connect-to-BiDi API, MCP extension mode is
Chromium-only). Playwright *can* launch **native** Firefox itself (`moz-*`
channels, WebDriver BiDi) — but only into a profile it owns, and its BiDi
implementation **cannot even see pre-existing tabs**, let alone list or spare
them. "Open one tab in the live session without touching the rest" is trivially
achievable without Playwright (`firefox -new-tab URL`); "control that tab with
Playwright" is not achievable today without restarting the live browser under
automation flags *and* using a non-Playwright BiDi client.

**Home.** The maintained synthesis of this topic is
[`/doc/playwright/README.md`](/doc/playwright/README.md) (parent-maintained,
integrating this verdict). This file stays an independent `draft`-status wave
report: the evidence record and full citation trail behind that README, kept
under wave discipline rather than promoted, and revisable here without
rewriting the maintained home.

## Summary matrix

| Desired capability | Playwright CLI | Playwright MCP | Status |
| --- | --- | --- | --- |
| Attach to *running* native Firefox | ✗ `connectOverCDP` throws (Chromium/WebKit only) | ✗ `--cdp-endpoint` hardcodes `playwright.chromium.connectOverCDP` | **Unsupported** |
| Attach via Playwright protocol `connect()` | ✗ endpoint must be a `launchServer()` browser | ✗ same (`--endpoint`) | **Unsupported** — Firefox running normally speaks no Playwright protocol |
| Attach via WebDriver BiDi | ✗ no `connectToBiDi` API exists | ✗ none exposed | **Unsupported in Playwright** (protocol itself exists, see §C) |
| Extension bridge into running browser | n/a | ✗ `--extension` is "Edge/Chrome only", built on `chrome.debugger` CDP relay | **Unsupported for Firefox** |
| Launch *native* Firefox under control | ✓ `channel: 'moz-firefox*'` → BiDi | ✓ `--browser moz-firefox[-beta|-nightly]` | **Supported** — but Playwright owns the profile; existing tabs invisible |
| Launch patched Firefox (Juggler) | ✓ default `firefox` | ✓ `--browser firefox` | **Supported** — separate download, own profile |
| Point `launchPersistentContext` at the *live* profile dir | ✗ practically: profile lock + pref rewrites | ✗ same | **Do not** — see §D |

## A. The two Firefox worlds in current Playwright

Default `firefox` is the **patched build** speaking Juggler over a pipe:
`-no-remote -profile <dir> -juggler-pipe` are forced args, and passing
`-profile`/`-juggler` yourself is rejected
(`packages/playwright-core/src/server/firefox/firefox.ts:91-113`, readiness at
:115-122). This build is a Playwright-managed download; docs state plainly
"Playwright doesn't work with the branded version of Firefox since it relies on
patches" (`docs/src/browsers.md:582-584`).

Newer and quieter: `channel: 'moz-*'` reroutes `launch`/`launchPersistentContext`
to a **BidiFirefox** browser type (`server/firefox/firefox.ts:44-54`; wiring at
`server/playwright.ts:62`). `moz-firefox`, `moz-firefox-beta`, `moz-firefox-nightly`
resolve to the **system Firefox binary** — e.g. `/snap/bin/firefox` on Linux
(`server/registry/index.ts:667-681`). Launch args become
`--remote-debugging-port=0 --foreground --profile <dir>`
(`server/bidi/bidiFirefox.ts:107-122`); readiness is the stderr line
`WebDriver BiDi listening on ws://…` (:124-132). So *native, unpatched* Firefox
under Playwright control is now a first-class path — but strictly as a
**launch**, never an attach.

## B. Why no attach surface exists for Firefox

- **CDP:** server side, non-Chromium `connectOverCDP` throws
  "CDP connections are only supported by Chromium"
  (`server/browserType.ts:287-296`); client side, Firefox `connectOverCDP`
  throws "Connecting over CDP is only supported in Chromium and WebKit"
  (`client/browserType.ts:146-147,157-158`). Runtime-verified on published
  playwright-core 1.64.1: exact same error. Firefox upstream, for its part,
  has **ended CDP support** — WebDriver BiDi "is the only available protocol",
  the `remote.active-protocols` pref was removed in Firefox 141
  (firefox-source-docs, *Remote protocol preferences*). So neither side of a
  CDP attach exists anymore.
- **Playwright protocol:** `browserType.connect()` speaks only Playwright's
  own protocol and requires the endpoint's handshake to yield
  `preLaunchedBrowser` — else "Malformed endpoint. Did you use BrowserType
  launchServer method?" (`client/connect.ts:29-75`, esp. :58-61). A normal or
  BiDi-enabled Firefox has no such server.
- **MCP attach modes** (`tools/mcp/browserFactory.ts:63-91` in the playwright
  monorepo — note `@playwright/mcp` is now a thin CLI wrapper, its repo's
  `src/` just points back at the monorepo):
  - `--cdp-endpoint` → `createCDPBrowser` hardcodes
    `playwright.chromium.connectOverCDP` (`browserFactory.ts:129-139`).
  - `--endpoint` → Playwright-protocol remote/`launchServer`
    (`browserFactory.ts:155-184`), same constraint as `connect()`.
  - `--extension` → launches a local WebSocket CDP relay bridging the
    "Playwright Extension" and then `playwright.chromium.connectOverCDP`
    (`tools/mcp/extensionContextFactory.ts:29-50`; relay in `cdpRelay.ts`).
    The flag's own help text: "Connect to a running browser instance (Edge/Chrome only)"
    (`tools/mcp/program.ts:52`). It is built on Chromium's `chrome.debugger`;
    Firefox has no equivalent. Also note `resolveExtensionOptions` defaults the
    channel to `'chrome'` when `--browser` yields no channel
    (`tools/mcp/config.ts:218-224`) — `--extension --browser firefox` silently
    targets Chrome, it does not error.
- **No connect-to-BiDi API:** the BiDi implementation is reachable only
  through launch (`moz-*` channels). Nothing in `client/browserType.ts` or the
  MCP config exposes a BiDi endpoint URL. (Contrast Puppeteer, which can
  `connect` to a BiDi wsURL — out of scope here, but it is the honest
  "supported protocol, other client" answer.)

## C. Even a hypothetical attach wouldn't see the 1000 tabs

Playwright's BiDi layer is instructive about what attach-grade support would
look like, and currently it is adoption-free:

- On connect it sends `session.new`, subscribes browser-wide to
  `browsingContext`, `network`, `log`, `script`, `input` events, adds a global
  **AuthRequired network intercept** and a **response data collector with a
  20 MB cap** (`server/bidi/bidiBrowser.ts:55-103`). Note for later: a
  Playwright BiDi session is *not* passive — it hooks the browser's network
  pipeline from the moment it attaches.
- It **never enumerates existing contexts** (no `browsingContext.getTree` on
  connect). Pages are only discovered from `browsingContext.contextCreated`
  events *after* attach (`bidiBrowser.ts:156-183`). For persistent contexts it
  creates a fresh page, with the comment "we cannot get access to the existing
  one" (`bidiBrowser.ts:94-101`).
- `context.newPage()` maps to `browsingContext.create` with
  `type: 'window'` (`bidiBrowser.ts:282-291`; enum
  `third_party/bidiProtocolCore.ts:711-716`) — per source reading, on Firefox
  this opens a **new window**, not a tab in an existing one (this session did
  not runtime-test a native moz-firefox launch).
- `page.title()` — which MCP tab listings call per tab (see §F) — is a script
  evaluation `document.title` **inside the page's own realm**
  (`server/frames.ts:1717-1729`), i.e. it touches each tab it names.
  `selectTab` → `page.bringToFront()` → `browsingContext.activate`
  (`tools/backend/context.ts:212-220`; `server/bidi/bidiPage.ts:375-379`) —
  genuine activation/focus side effect. (Whether a BiDi script evaluation
  *wakes a Firefox-unloaded tab* is Firefox-internal behavior I could not
  verify from these trees; treat "listing may wake" as plausible, not proven.
  The WebExtension `tabs.query` route, by contrast, serves title/url from
  session state without reload — that much is standard extension-API behavior.)

So the 1000 existing tabs are invisible to Playwright-BiDi by construction:
no listing, no accidental close *through Playwright's page objects* — and also
no way to satisfy "list them" via Playwright. The blast-radius risk in BiDi
mode is inverted: the danger is not per-tab poking but **session-level**
operations (§E).

## D. "Just point it at the real profile" — why that fails twice

Mechanically `firefox.launchPersistentContext(realProfileDir,
{ channel: 'moz-firefox' })` is expressible. It is a dead end:

1. **Profile lock.** Firefox allows one instance per profile (lock file in the
   profile dir; `-no-remote` exists precisely to opt out of remoting into a
   running instance — MozillaWiki *CommandLineOptions*). The live 1000-tab
   Firefox holds the lock. A second launch against the same dir either
   remotes into the existing instance (BiDi launch args carry **no**
   `-no-remote`, `bidiFirefox.ts:107-122`) — in which case the launcher exits
   and Playwright's `waitForReadyState` times out — or collides with the lock.
   The MCP's pre-flight lock check reads Chromium's `SingletonLock`/`lockfile`
   convention only (`tools/mcp/browserFactory.ts:243-276`), so it will not even
   give you a friendly Firefox-specific error.
2. **Pref rewrites.** Playwright's `prepareUserDataDir` runs for persistent
   launches too (`server/browserType.ts:165-174`) and BidiFirefox writes a
   Puppeteer-derived `user.js` full of automation prefs into the profile
   (`server/bidi/bidiFirefox.ts:100-105`;
   `server/bidi/third_party/firefoxPrefs.ts:19-32` and the ~40 defaults from
   :34 onward). Independently, Firefox's own Remote Agent "attempts to set a
   range of preferences deemed suitable in automation when it starts"
   (`remote.prefs.recommended`, firefox-source-docs *Prefs*). A copied profile
   fares no better: `user.js` still applies, and Playwright's Juggler path
   requires its patched binary anyway.

Also worth knowing: with `--remote-debugging-port` active, any local process
can drive the browser while it listens — the remote agent is a debugging
surface, not an authenticated one (firefox-source-docs, *Security aspects of
the Remote Agent*).

## E. Teardown and accidental-close semantics (the real risk profile)

- **MCP adopts the first context it sees.** Non-isolated mode takes
  `browser.contexts()[0] ?? newContext()` (`tools/mcp/program.ts:153-161`).
  In persistent mode that is the *default context owning every tab*.
- **Dispose closes adopted context + browser.** Last client disconnect or
  `browser_close` runs `browserContext.close()` then `browser.close()`
  (`program.ts:163-187`; `tools/backend/browserBackend.ts:137-140` → backend
  dispose). **For launch-owned persistent contexts** this escalates:
  `doClose` returns `'close-browser'` → full `browser.close()`
  (`server/bidi/bidiBrowser.ts:531-540`; same pattern in
  `server/chromium/crBrowser.ts:557-567` and `server/firefox/ffBrowser.ts:398-401`;
  escalation consumer at `server/browserContext.ts:550-557`). In one tool call
  ("close browser"), a *launch-owned* persistent session goes down — the
  1000-tab exposure would exist if the live profile were ever launched under
  Playwright, which §D rules out anyway.
- **Attach-mode teardown is a different case and was not traced to a
  confirmed browser-side close.** For `connect()`-style browsers the client
  `Browser.close()` only drops the connection
  (`client/browser.ts:183-196` with `_shouldCloseConnectionOnClose`), so the
  MCP dispose's `browser.close()` there is a disconnect, not a browser
  termination. Whether the MCP factory's dispose path, run against a CDP or
  extension-mode *attached* browser, ultimately closes the real browser (or
  merely detaches and tears down the relay) depends on attach-mode
  `BrowserOptions.browserProcess` plumbing this investigation did not follow
  to a verified end — flagged unverified rather than projected either way.
- **CDP attach caveat for the Chromium analogy:** persistent CDP connects run
  `Target.setAutoAttach` with `waitForDebuggerOnStart: true`
  (`server/chromium/crBrowser.ts:84-99`) — attaching pauses new targets until
  resumed, which is why MCP-extension-mode sessions can make a live Chrome
  feel briefly sticky on new tabs. Firefox-BiDi has no such pause, but does
  have the global intercept/collector noted in §C.
- **Accidental navigation** is per-tab and deliberate in MCP (`browser_navigate`
  on the current tab); the practical foot-gun is `browser_tabs close` with a
  wrong index against a shared tab list, and idle timeouts closing the browser
  (`--idle-timeout` default 1 h headless; `program.ts:55-58` in
  `browserFactory.ts`).

## F. Tab listing cost (applies wherever tabs *are* visible)

MCP's `browser_tabs list` maps every tab in the adopted context to
`headerSnapshot()`, which awaits `page.title()` **and** a console/error count
per tab (`tools/backend/tabs.ts:37-66`; `tools/backend/tab.ts:299-324`,
console counts at :402-415). The per-tab headers are gathered concurrently
(`Promise.all` over tabs, `tabs.ts:63`), so this is not serial waiting — but
the work is still O(N) in tab count, and it distinguishes into layers:

- `page.title()` is an **in-page script evaluation** (`document.title` in the
  page realm, `server/frames.ts:1717-1729`) — a browser-protocol round trip
  per tab that touches the tab it names. Whether it wakes a Firefox-unloaded
  tab is Firefox-internal behavior this investigation did not verify; treat
  "listing may wake" as plausible, not proven.
- The console/error counts go through `page.consoleMessages()` /
  `page.pageErrors()` (`client/page.ts:752-764`) — Playwright-channel calls
  answered from state the server side already buffers from its event
  subscriptions; these need not trigger new browser-protocol round trips.

Net: per listing, N in-page title evaluations plus channel-level count
fetches, and an N-entry tab-header payload in the tool response. At ~1000
tabs that is a large operation and may be slow; no quantitative timing is
claimed here (nothing was benchmarked). On moz-firefox the question is moot
(only Playwright-created tabs are visible); on Chromium-CDP attach modes it
would be very real. Snapshots (`browser_snapshot`) are scoped to the selected
tab only — safe by comparison.

## G. Recommended paths, least-invasive first

- **A. Open a tab in the live session, no automation at all.**
  `firefox -new-tab URL` (or plain `firefox URL`) is a *remote command*: the
  launcher hands it to the running instance and exits (MozillaWiki
  *CommandLineOptions*; `-no-remote` documents the inverse). It makes no
  automation configuration, relaunch, or protocol changes — though ordinary
  browsing itself persists state (the new tab lands in the session store and
  history like any user-opened tab). This satisfies the "open a new tab,
  leave others alone" half of the ask. Works under snap packaging.
- **B. Playwright-driven Firefox, parallel to the live session.** Run MCP
  (`--browser moz-firefox` for native, `--browser firefox` for patched) with
  its own profile — default is a per-workspace persistent dir under the
  Playwright cache (`browserFactory.ts:225-233`), or `--isolated` for
  in-memory, or a dedicated `--user-data-dir`. Fully supported today; zero
  contact with the live profile; cannot see the 1000 tabs (which is precisely
  the isolation property you want). New pages open as new *windows*
  (`type:'window'`, §C) — cosmetic, but know it.
- **C. Actually drive the live session: BiDi with a non-Playwright client.**
  Restart Firefox once with `--remote-debugging-port` (session restore brings
  the tabs back), then a raw WebDriver-BiDi client (or Selenium 4.x BiDi
  support) can `browsingContext.create` a tab and drive it while
  `browsingContext.getTree` lists the rest read-only. Costs: one restart;
  automation prefs set at remote-agent start (§D.2); unauthenticated localhost
  debugging surface while enabled. **Playwright cannot be that client today**
  (§B), so this exits the Playwright toolbox.
- **D. In-profile WebExtension.** The only route with native per-tab
  granularity inside the live profile (`tabs.query` sees discarded tabs from
  session state without waking them; `tabs.create` opens a tab; scripting APIs
  drive it). But installing an extension is a real, persistent profile change,
  and bridging it to an agent (native messaging / local socket) is custom
  infrastructure — explicitly out of scope per the commission's "no custom
  safeguards". Recorded as the shape of the Firefox-native answer, not a
  recommendation.
- **E. If the browser were Chromium.** MCP `--extension` mode is built for
  exactly this ask — attach to the *running* Chrome/Edge, per-tab control via
  `chrome.debugger`, no restart, profile untouched apart from having the
  extension installed. No Firefox equivalent exists or is plumbed (§B).

**What would change the verdict:** Playwright gaining a
connect-to-WebDriver-BiDi entry point (nothing in tree as of b335271c); MCP
extension mode growing a Firefox bridge (blocked on `chrome.debugger` being
Chromium-only); Firefox resurrecting CDP (removed, opposite direction).

## Appendix: verification log

- Archives read at the commits in frontmatter; no other checkouts consulted
  for Playwright claims.
- Disposable probes (published `playwright-core@1.64.1`, `/tmp/opencode`,
  no browser launched): `firefox.connectOverCDP('http://127.0.0.1:9/')` →
  "Connecting over CDP is only supported in Chromium and WebKit.";
  `firefox.connect('ws://127.0.0.1:9/session')` → plain WebSocket ECONNREFUSED
  (i.e. it only speaks the Playwright protocol); `firefox.launch({args:['-profile',…]})`
  → "Pass userDataDir parameter to 'browserType.launchPersistentContext'…".
- Constraint compliance: the user's actual browser/profile was never attached
  to, launched, copied, or inspected; no MCP server was started; probes above
  failed client-side before any process spawn.
- No native `moz-firefox` launch was runtime-tested by this session; every
  moz-*/BiDi claim rests on source reading alone.
- Reported by the commissioning session (not verified here, and distinct from
  the moz path): installed `@playwright/mcp` 0.0.83 and Playwright CLI 0.1.22
  driving **separate patched-Firefox profiles** (Juggler builds), headless
  and headed, through live OpenCode sessions — no real user browser or
  profile touched. That validates recommendation B's patched-build leg.
