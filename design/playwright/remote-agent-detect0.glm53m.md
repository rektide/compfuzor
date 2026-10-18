---
type: Report
title: Firefox remote-agent automation detection surface — source trace into gecko-dev
description: Exact file:line trace of how navigator.webdriver becomes true under WebDriver BiDi (live cross-process shared-data, not a pref), the complete remote.prefs.recommended enumeration with observability classification, BiDi network-layer mutation audit, every other activation-time mark, and the supported/unsupported verdict for BiDi-without-webdriver.
resource: /design/playwright/remote-agent-detect0.glm53m.md
status: draft
author: rektide (commission); model:glm-5.3#max (investigation and report)
generated:
  at: 2026-10-18
  by: model:glm-5.3#max
ticket: ""
tags: [firefox, webdriver, webdriver-bidi, remote-agent, navigator-webdriver, playwright, anti-bot, detection, source-trace]
sources:
  - resource: opencode://ses_eaf8225bdffePtIv2dlUZgAGb3
    title: Commissioning session — Google sign-in rejects automated Firefox while branded CDP Chrome passes; eliminated-hypotheses list; question and method constraints
  - resource: opencode://ses_eaf1f092fffe8trsEvcIFRYZgD
    title: Investigation session (misty-circuit) — gecko-dev source reading, cross-process flag trace, prefs enumeration, network-stack audit, playwright-core store probe, report
  - resource: /home/rektide/archive/mozilla/gecko-dev
    title: mozilla gecko-dev fresh clone (11.4GB, 2026-10-18) — all file:line citations below; tree was deleted from disk mid-session (disk pressure), citations are from reads completed before removal
  - resource: /home/rektide/.local/share/pnpm/store/v3
    title: Installed playwright-core copies (pnpm store v3) — disposable grep probe of the Firefox launcher preference list; no browser launched
verification: >
  Every gecko-dev claim was read directly this session with the cited line
  numbers; the tree vanished from disk before final re-verification of two
  browser/ cites (noted inline), which came from rg output captured earlier
  in-session. No browser was launched against any profile; the only
  client-side probe was reading published playwright-core text from the pnpm
  store. Line numbers drift with upstream; re-grep the named symbols in a
  fresh mozilla-central checkout when in doubt.
---

# Firefox remote-agent automation detection surface

**Situation.** Google sign-in rejects Firefox under Playwright automation at
the email step ("This browser or app may not be secure") while branded Chrome
under CDP passes the same flow. Already eliminated empirically by the
commissioning session: `navigator.webdriver` masking (getters, descriptor
probes, `Function.toString` native checks), stock UA/buildID/oscpu/plugins/
mimeTypes/pdfViewerEnabled, wire-header shape, Puppeteer pref-set page markers
(popup blocker, ETP, Safe Browsing, HTTPS-First restored via
`firefoxUserPrefs`), human-like typing. Patched-Juggler Firefox and
stock-binary BiDi Firefox **both** reject. Working hypothesis: an
engine-level automation-active state detectable below page-JS/header/pref
layers. This wave answers, from Firefox source, where that state lives, what
else activation changes, and whether BiDi can run without it.

Sibling wave: [`live-firefox0.glm53m.md`](/design/playwright/live-firefox0.glm53m.md)
(attach-vs-launch surfaces). Maintained topic home (parent-maintained):
`/doc/playwright/README.md`.

## 1. How `navigator.webdriver` becomes true — the mechanism

It is **not a preference, not computed at page init, and not cached**. It is a
live query of remote-agent *service running state*, replicated cross-process
via chrome-only shared data.

Trace, all paths relative to the gecko-dev tree root:

1. **Declaration.** `dom/webidl/Navigator.webidl:311-314` —
   `readonly attribute boolean webdriver;`, commented with the WebDriver spec
   interface link. It is an accessor on `Navigator.prototype`, so every realm
   (every window, every iframe, fresh or pre-existing) re-evaluates it on
   every access.

2. **Implementation.** `dom/base/Navigator.cpp:2284-2307`
   (`Navigator::Webdriver()`, static): queries
   `do_GetService(NS_MARIONETTE_CONTRACTID)->GetRunning()` and, if not
   running, `do_GetService(NS_REMOTEAGENT_CONTRACTID)->GetRunning()`. Returns
   true if either is running. Compiled only under `ENABLE_WEBDRIVER`
   (`Navigator.cpp:82-85`; build flag `toolkit/moz.configure:1418-1433`,
   `--disable-webdriver` is a **build-time** configure option, not runtime —
   stock Firefox ships with it enabled).

3. **Who resolves the service in a content process.** The XPCOM component is
   registered process-agnostically (`remote/components/components.conf`:
   contract `@mozilla.org/remote/agent;1`, categories
   `command-line-handler m-remote` and `profile-after-change`). The module
   branches on process type (`remote/components/RemoteAgent.sys.mjs:28-29`):
   the parent gets `RemoteAgentParentProcess`; every content process gets
   `RemoteAgentContentProcess` (`:514-522`), whose `running` getter returns
   `Services.cpmm.sharedData.get("RemoteAgent:Active") ?? false` (`:516`). The
   key constant is `SHARED_DATA_ACTIVE_KEY = "RemoteAgent:Active"`
   (`:26`). There is also a sync-IPC fallback message
   `RemoteAgent:IsRunning` (`:485-493`).

4. **When the flag is set.** `RemoteAgentParentProcess.observe` sees
   `--remote-debugging-port` at `command-line-startup` (`:427-434`), applies
   recommended prefs (`:447`), constructs `WebDriverBiDi` (`:449`), and on
   `final-ui-startup` calls `#listen(port)` (`:454-461`). `#listen`
   (`:233-323`) binds the httpd.js server and then — unconditionally, with no
   pref or flag consult — calls `updateWebdriverActiveFlag(true)` (`:309`),
   which does `Services.ppmm.sharedData.set("RemoteAgent:Active", true)` +
   `flush()` (`:146-149`), then notifies `remote-listening` (`:311`) and
   starts BiDi (`:313`). `#stop()` clears the flag (`:392`). Consequences:

   - The flag is **browser-global and set before any web content loads**
     (final-ui-startup precedes first paint), flushed to *all* content
     processes, including every fission process spawned later.
   - Each `navigator.webdriver` read is a **live** lookup; nothing is baked
     into a realm at creation. Playwright's init-script masking must defeat
     the accessor in every realm individually; the underlying state is
     untouched by masking. Any realm the masking does not cover (an initial
     `about:blank` created before script registration, PDF-viewer sandboxes,
     `data:`/`srcdoc` edge paths) still exposes the native accessor returning
     `true`.
   - Mere *listening* flips it — no BiDi WebSocket session, no client
     command, ever needs to connect. From Playwright's launch until browser
     shutdown, the state is true. Marionette mirrors the identical pattern
     (`remote/components/Marionette.sys.mjs:24` key `"Marionette:Active"`,
     `:94-97` setter, `:233`/`:258` set/clear, `:285-287` content getter),
     so `--marionette` runs are flagged the same way.

5. **Channels page JS cannot reach (Q1 answer).** The state itself
   (`ppmm/cpmm.sharedData`) is chrome-only; web content has no API to read
   `RemoteAgent:Active` directly. There is **no** other content-side
   reflection of it in the tree — no header, no timing hook, no
   PerformanceObserver path, no chrome-privileged API reachable from content.
   Workers are *not* a channel: `dom/webidl/WorkerNavigator.webidl` has no
   `webdriver` attribute (verified by absence; `rg -i webdriver
   dom/workers/` is empty), and the page-visible accessor exists only on
   `Navigator`. Indirect reflections that exist, none of them readable by
   page JS or by a web server on the browsing traffic itself:

   - Glean page-load perf telemetry records `usingWebdriver` from the
     parent-side check (`dom/ipc/ContentParent.cpp:6237-6263`,
     `WebdriverRunning()` + `RecvRecordPageLoadEvent`). Mozilla-side sink
     only — and recommended prefs point `toolkit.telemetry.server` at a dummy
     URL anyway (§2), so it never leaves the machine.
   - Crash-report annotation `RemoteAgent=true`
     (`RemoteAgent.sys.mjs:439`; Marionette equivalent
     `Marionette.sys.mjs:137`).
   - Browser UI "remote control" visual cue: front-end observes
     `remote-listening` (captured in-session from
     `browser/base/content/browser-init.js:358-360`, cue update at `:258`,
     observer removal `:1074-1076`; comment in `browser.js:4408`) — a
     toolbar/urlbar indicator, visible to a human or screen capture, not to
     the page or a web server.
   - The local listening socket (default port 9222,
     `RemoteAgent.sys.mjs:498-500`; Playwright passes `0` → ephemeral). A web
     page on an https origin cannot probe it (mixed content blocks
     http/localhost subresources in Firefox); only local software sees it.
   - `WebDriverBiDiServer.json` written into the profile
     (`remote/webdriver-bidi/WebDriverBiDi.sys.mjs`, `start()` around
     `:226-233`) — profile-local, not page/server visible.

## 2. `remote.prefs.recommended` — exact application and full enumeration

**Activation path (BiDi).** With `--remote-debugging-port` present, the agent
applies the common recommended set at `command-line-startup`
(`RemoteAgent.sys.mjs:447`) and WebDriver BiDi merges a protocol-specific
extra set when BiDi starts (`remote/webdriver-bidi/WebDriverBiDi.sys.mjs:24-33`
definition, `:218` applied inside `start()`). All of it flows through
`RecommendedPreferences.applyPreferences`
(`remote/shared/RecommendedPreferences.sys.mjs:401-442`), which:

- is gated on the pref `remote.prefs.recommended` (`:13-18`, `:402-406`);
  default **true** (`modules/libpref/init/all.js:3907`), so *setting it to
  `false` in the profile user.js before launch skips every recommended pref,
  common and BiDi-specific alike* — documented at `remote/doc/Prefs.md:41-51`
  and `testing/geckodriver/doc/Profiles.md:82-84`;
- **never overrides user-set values**: `if
  (!Services.prefs.prefHasUserValue(k))` (`:420`). Any pref the client writes
  into the profile user.js (Playwright's `firefoxUserPrefs`) is left alone;
  the agent only fills gaps;
- sets a marker `remote.prefs.recommended.applied=true` (`:344`) and restores
  everything it changed on `quit-application` (`:444-449`, `:465-471`).

Marionette applies the same shared set only under `--marionette` /
`MOZ_MARIONETTE` (`Marionette.sys.mjs:55`, `:125-142`), and additionally
propagates env-preserved prefs via `MOZ_MARIONETTE_PREF_STATE_ACROSS_RESTARTS`
(`:42`, `:147`). Irrelevant to a BiDi run.

**The complete common list** (`COMMON_PREFERENCES`,
`RecommendedPreferences.sys.mjs:83-386`), classified by what can observe it.
"Mozilla-net" = network silence/dummy-redirect of Mozilla-operated endpoints
(only observable as *absence* to those endpoints, not to Google).

Page-behavior-visible (probe-able by web JS):

| Pref | Line | Stock | Note |
|---|---|---|---|
| `browser.dom.window.dump.enabled=true` | 109 | **false** (official builds, `all.js:623`, `StaticPrefList.yaml:1595-1598`) | **exposes `window.dump()` to ordinary web content** — `nsGlobalWindowInner.cpp:3677-3678` gates `Window.dump` on `nsJSUtils::DumpEnabled()` (`nsJSUtils.cpp:157-168`, release builds read the pref). Stock official Firefox does not define `dump` on windows; an agent-active one does. |
| `dom.disable_open_during_load=false` | 221 | true | popup blocker off (parent restored via user pref). |
| `privacy.trackingprotection.enabled=false` | 341 | true | ETP tracking protection off (parent restored). |
| `dom.successive_dialog_time_limit=0` | 255 | >0 | dialog-abuse suppression off (stock default not re-verified — tree removed; historically 3s). |
| `dom.navigation.navigationRateLimit.count=0` | 246 | >0 | navigation rate limiting off. |
| `dom.max_script_run_time=0`, `dom.max_chrome_script_run_time=0` | 242-243 | >0 | slow-script watchdog off (timing-side probes only). |
| `security.fileuri.strict_origin_policy=false` | 351 | true | file:// documents only. |
| `dom.input_events.security.minNumTicks=0`, `...minTimeElapsedInMS=0` | 227-228 | >0 | input-event security delay off (timing-side). |

Google-server-visible (tracker/safe-browsing endpoints see traffic a stock
Firefox would not send, or vice versa):

| Pref | Line | Effect |
|---|---|---|
| `browser.safebrowsing.blockedURIs.enabled=false` | 145 | Safe Browsing blocked-URI lookups off |
| `browser.safebrowsing.downloads.enabled=false` | 146 | download scanning off |
| `browser.safebrowsing.malware.enabled=false` | 147 | malware lists off |
| `browser.safebrowsing.phishing.enabled=false` | 148 | phishing lists off — these four hit **Google-operated** list/update endpoints in stock; parent restored SB via user prefs, so the agent skips them |

Mozilla-net silences/dummies (absence-only signals, not visible to Google):
`app.normandy.api_url=""` (85), `app.update.disabledForTesting=true` (92),
newtab weather/wallpaper/sponsored/Contile (120-129, 190),
`browser.region.network.url=""` (139), search-engine updates (153),
`browser.urlbar.merino.endpointURL=""` (197),
`browser.urlbar.suggest.searches=false` (201), datareporting/health-report
set (208-218), `identity.fxaccounts.auth.uri` dummy (323),
`network.connectivity-service.enabled=false` (326), SNTP dummy (338),
`security.remote_settings.intermediates.enabled=false` (357) +
`services.settings.server="data:,...` (363) + loglevel off (360),
`toolkit.telemetry.server` dummy (381), `dom.push.connection.enabled=false`
(249), `geo.provider.network.url=""` / `geo.wifi.scan=false` /
`geo.provider.testing=true` (313-320), extensions update/blocklist/discovery
dummies (265-304), `general.useragent.updates.enabled=false` (310),
`network.http.phishy-userpass-length=255` (329), MITM priming off (347),
`security.notification_enable_delay=0` (354).

Not page- or network-observable (UI/session ergonomics): APZ timeout (101),
contentblocking introCount (106), download panel shown (114),
blank-page-with-error (117), newtab disabled (132), thumbnails (136),
session-restore (156), default-browser check (162), startup counters/mstone
(165-168), tab unload behavior (171-174, 239), tab warnings (177-204),
bookmarks toolbar (187), Windows intro URL (193), `dom.file.createInChild`
(224), ProcessHangMonitor off (231), thread priority management (238),
screen-orientation allow-lock (252), extension scopes (261-262, 269),
`focusmanager.testmode=true` (307), `network.http.prompt-temp-redirect=false`
(332), `network.manage-offline-status=false` (335), signon autofill/remember
(367, 371), startup welcome URLs (374-375), `toolkit.startup.max_resumed_crashes`
(378), Windows window-occlusion (385), marker pref (344).

**BiDi-specific extras** (`WebDriverBiDi.sys.mjs:24-33`):

- `permissions.isolateBy.userContext=true` — stock false
  (`StaticPrefList.yaml:15543-15546`). No page-observable difference found
  for the default user context.
- `network.http.rcwn.enabled=true` — **stock desktop default is already
  true** (`StaticPrefList.yaml:13228-13235`; Android-only stock is false), so
  no behavioral delta on desktop despite looking alarming.

## 3. BiDi network-layer marks (Q3)

Default posture is **observation-only**; nothing mutates traffic unless the
client explicitly commands it:

- Network event capture wraps the devtools observer
  (`remote/shared/listeners/NetworkListener.sys.mjs:10` imports
  `resource://devtools/shared/network-observer/NetworkObserver.sys.mjs`) —
  passive.
- Header/redirect mutation exists only inside explicit BiDi interception
  continuation commands (`remote/webdriver-bidi/modules/root/network.sys.mjs:574`
  setRequestHeader, `:592-599` Cookie rewrite, `:612` redirectTo) — reachable
  only after the client registers intercepts and continues requests. Playwright
  does none of this unless `route()` is used.
- HTTP cache stays enabled by default
  (`remote/shared/NetworkCacheManager.sys.mjs:33-54`, default
  `CacheBehavior.Default`); bypass only via `network.setCacheBehavior`.
- TLS stack untouched unless the session capability `acceptInsecureCerts` is
  requested (`remote/shared/webdriver/Session.sys.mjs:240-244` →
  `Certificates.disableSecurityChecks`,
  `remote/shared/webdriver/Certificates.sys.mjs:40-60`: HSTS preload list off
  `:47`, certificate pinning enforcement 0 `:51`, gated by the automation
  check in `security/manager/ssl/nsCertOverrideService.cpp:628-660`
  `IsDebugger()` — the same Marionette/RemoteAgent running query). Playwright
  requests it only with `ignoreHTTPSErrors`.
- No `User-Agent` or header injection anywhere in `remote/` (the only
  "userAgent" references are read-only capability plumbing in
  `remote/shared/webdriver/Capabilities.sys.mjs` and legacy Selenium atoms in
  `remote/marionette/atom.sys.mjs`).

Consistent with the commissioning session's wire capture: basic navigation
headers match stock — and the source confirms nothing conditional is waiting
to diverge.

## 4. Everything else activation does (Q4)

Enumerated exhaustively above: prefs (§2), crash annotation, UI cue, shared
flag + sync-IPC query, profile `WebDriverBiDiServer.json`, local socket, env
vars (`MOZ_REMOTE_ALLOW_SYSTEM_ACCESS` only when the flag is passed,
`RemoteAgent.sys.mjs:24,46,100-106`; `MOZ_MARIONETTE=1` only for Marionette,
`Marionette.sys.mjs:29,55,235`). `toolkit.telemetry` is overridden only via
the recommended list (server dummy, `:381`). **Juggler is not in-tree**:
zero real hits for "juggler" in the whole tree (only dictionary/safelist
false positives) — Playwright's patched Firefox is an out-of-tree patchset
with no gecko-dev equivalent to audit, and its rejection alongside stock BiDi
further implicates the shared in-tree surface (flag + prefs + Playwright
client prefs), not Juggler itself.

**Playwright client-side (probe of installed playwright-core, pnpm store v3 —
three copies, all matching).** The Firefox launcher's profile preference list
(the Puppeteer-derived list, jest-puppeteer comments intact) sets
`'browser.dom.window.dump.enabled': true` **and**
`'browser.contentblocking.features.standard':
'-tp,tpPrivate,cookieBehavior0,-cm,-fp'`. Two consequences for the
commissioning campaign:

1. **`window.dump` is live in *both* rejected configurations** — Playwright
   writes it true for every Firefox launch (patched Juggler and BiDi
   `moz-firefox` alike), and even if it did not, the agent's recommended
   prefs would (§2 line 109; no user value → agent fills it). Stock official
   Firefox leaves `typeof window.dump === "undefined"` in content. This is a
   concrete page-JS automation tell surviving every masking the commissioning
   session performed (their restoration list — popup blocker, ETP, SB,
   HTTPS-First — does not include it). Chrome passes; Chrome has no `dump`.
2. **The ETP restoration is likely incomplete**: restoring
   `privacy.trackingprotection.enabled=true` re-enables TP, but Playwright's
   user.js `browser.contentblocking.features.standard` string still ships
   `cookieBehavior0` (no Total Cookie Protection/dFPI), `-cm`, `-fp` — so
   tracker-class requests that a stock-standard Firefox blocks will still
   fire, visible to any tracker endpoint Google correlates. Fix: also set
   `browser.contentblocking.features.standard` to the stock value in
   `firefoxUserPrefs` (it is a user pref, so the agent never touches it).

## 5. Verdict (Q5)

**There is no supported way to run WebDriver BiDi without
`navigator.webdriver === true`, and that is by design.**

- The truth source is live remote-agent *listening* state replicated to all
  content processes (`RemoteAgent.sys.mjs:26,146-149,309,392,514-522`;
  `Navigator.cpp:2284-2307`). No pref, flag, env var, or capability gates
  `updateWebdriverActiveFlag` — grep of the whole `remote/` tree finds no
  condition around either call site. The only switch that removes it is the
  **build-time** `--disable-webdriver` (`toolkit/moz.configure:1418-1433`),
  which removes remote protocols entirely — no BiDi either. The webidl itself
  anchors the property to the WebDriver spec
  (`Navigator.webidl:311-313`), which mandates true under automation control;
  Marionette and the remote agent implement one shared semantic.
- The CDP-Chrome asymmetry is therefore structural: Chrome's CDP attach flips
  no spec-mandated page-visible bit, while Firefox flips a browser-global one
  from first listen until shutdown. Any Firefox automation via
  Marionette/BiDi carries it; masking is per-realm page JS, nothing more.
- What **is** supported: `user_pref("remote.prefs.recommended", false)` in
  the profile before launch kills the entire recommended-pref surface
  (common + BiDi extras; `all.js:3907` default true; gate at
  `RecommendedPreferences.sys.mjs:402-406`; docs `remote/doc/Prefs.md:41-51`).
  Combined with per-pref user.js precedence (`:420`), the pref surface can be
  made fully stock: set `remote.prefs.recommended=false`, and where
  Playwright's own user.js already wrote a non-stock value (dump, the ETP
  features string), explicitly overwrite with stock values in
  `firefoxUserPrefs`.
- What remains after both, none of it page- or Google-server-readable:
  the webdriver flag itself (maskable per realm), the UI cue, the local
  socket, `WebDriverBiDiServer.json`, the crash annotation, and the (dummy-
  redirected) `usingWebdriver` telemetry field.

**Actionable residue for the campaign, in strength order:** (1) `window.dump`
presence — fix via `browser.dom.window.dump.enabled=false` user pref (stock
official value); (2) `browser.contentblocking.features.standard` neutering —
restore stock string; (3) `remote.prefs.recommended=false` to eliminate the
whole gap-filling surface at once. If rejection persists after those, the
surviving Firefox-side marks are only the ones no page or web server can read,
and the engine-level hypothesis would need to move to layers below this tree
(binary-identical TLS, profile freshness, IP/fingerprint scoring on Google's
side) — outside what Firefox source can adjudicate.

## 6. Method and limitations

Method: `rg`/`fd` over the fresh gecko-dev clone; direct file reads for every
cited range; one disposable read-only probe of installed playwright-core in
the pnpm store. No browser launches, no profile access, archive unmodified
(the tree was deleted externally mid-session; all reads used here completed
before that).

Limitations: line numbers are clone-moment snapshots of mozilla-central
(Firefox ~157-era, CDP already removed, BiDi-only); two `browser/` cites come
from captured rg output rather than a final re-read; stock defaults for
`dom.successive_dialog_time_limit` and `dom.navigation.navigationRateLimit`
were not re-verified before the tree vanished (flagged in §2). Whether
Google's risk engine actually probes any of the enumerated tells is not
answerable from Firefox source; this wave establishes exactly what the
surface is and is not.
