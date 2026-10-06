---
type: CapabilityAssessment
title: Kanata as a keyboard and Surface Dial event merger
description: Source-backed Linux input ownership, passthrough, device selection, chaining, and modifier-collision limits.
resource: /design/surface-dial-input/kanata-assessment0.gpt61s.md
status: draft
generated: { by: model:gpt-6.1-sol, at: 2026-10-06 }
stale_after: 2027-01-06
sources:
  - resource: https://github.com/jtroo/kanata/tree/v1.9.0
    title: Kanata v1.9.0 Linux backend and parser
  - resource: /kanata.srv.pb
    title: Main Kanata playbook
  - resource: /kinata.srv.pb
    title: Kinesis-specific Kanata playbook
  - resource: https://github.com/daniel5151/surface-dial-linux/tree/43dd973092871d8ef0c452b0797b519f5a9ddfac
    title: Surface Dial daemon source
---

# Question and verdict

Can the main Kanata instance put keyboard Shift and Surface Dial media keys onto one virtual keyboard so Umbriel can interpret the fine-volume chord?

**Yes, when both event streams actually enter that instance.** Kanata on Linux reads multiple evdev devices into one processing stream and emits one uinput device. With the current caps-only map, `process-unmapped-keys yes` retains Shift and media-key meanings without needing explicit Shift/volume entries. This is event merging, not automatic volume control: Umbriel must still consume `Shift+XF86AudioRaiseVolume/LowerVolume`.

**The present Kinesis split is an important exception.** [`kanata.srv.pb:31–58`](/kanata.srv.pb) excludes the Kinesis keyboard node but keeps its Consumer Control node. [`kinata.srv.pb:117–142`](/kinata.srv.pb) owns the keyboard, including Shift. Both outputs default to the name `kanata`; normal main-instance autodetection excludes that name. Consequently the playbooks do **not** currently consolidate Kinesis Shift with main-owned media keys. Whether Umbriel combines these separate keyboards is a compositor question, not a Kanata guarantee.

Also, the examined Surface Dial **already injects its own Left Shift with every volume click**. External keyboard Shift is unnecessary for its existing fine chord; holding Shift cannot by itself introduce a second, finer modifier level.

# Evidence and version boundary

The local checkout was inspected first: `/home/rektide/archive/jtroo/kanata`, clean Git state, HEAD `2f84d179de4dcf70f2a55818f9cddc102e544373` (2026-09-30), manifest `1.12.1-prerelease-1`. `/usr/bin/kanata --version` reported **1.9.0**. The local `v1.9.0` tag was therefore read with `git show`; the controlling references below target that version, not newer prerelease behavior. This verifies upstream capability corresponding to the reported version, not Debian patch equivalence or deployed configuration.

| Claim | Primary evidence |
|---|---|
| Multiple inputs, one output | [`v1.9.0 KbdIn`:31–136](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L31-L136) stores/grabs multiple devices; [`read`:140–158](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L140-L158) appends their events into one vector. [`KbdOut`:365–424](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L365-L424) constructs one virtual device, advertising key codes 0–559. |
| Unmapped Shift/media remain their ordinary keys | [`parser`:1172–1190](https://github.com/jtroo/kanata/blob/v1.9.0/parser/src/cfg/mod.rs#L1172-L1190) includes recognized key codes when enabled; the [`defsrc fallback layer`:2777–2788](https://github.com/jtroo/kanata/blob/v1.9.0/parser/src/cfg/mod.rs#L2777-L2788) supplies identity key actions. [`Linux event loop`:82–101](https://github.com/jtroo/kanata/blob/v1.9.0/src/kanata/linux.rs#L82-L101) routes processed keys through the shared layout. |
| Device provenance is lost in the keyboard event stream | [`read`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L140-L158) returns untagged `InputEvent`s; [`conversion`:319–327](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L319-L327) produces only code/value; [`layout input`:748–774](https://github.com/jtroo/kanata/blob/v1.9.0/src/kanata/mod.rs#L748-L774) uses coordinate `(0, keycode)`. |

“Untouched passthrough” should mean **unchanged key meaning**, not byte-for-byte timing, reports, or device identity. `process-unmapped-keys yes` sends Shift/media through the state machine; without it, unmapped events also go to the same output but take the raw path. It neither selects extra input devices nor combines outputs of separate instances automatically.

# Discovery: media-only is not necessarily excluded

The actual keyboard heuristic is **any supported key code in 1–115**, not an alphabetic-key requirement ([`has_keyboard_keys`:308–317](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L308-L317)). Mute, Volume Down, and Volume Up are 113, 114, and 115. Thus a media-only node advertising these keys can qualify by default. A transport-only node with none of that range may not. The source does not establish the live Kinesis Consumer Control node's capabilities.

The Surface Dial's `Surface Dial Virtual Keyboard/Mouse` explicitly advertises Shift, Ctrl, volume/mute, arrows, Space, Equal, and Minus: [`fake_input.rs:19–53`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L19-L53). It satisfies the keyboard heuristic; its wheel-only relative capabilities do not make it a mouse under the backend's `REL_X` test. Its separate virtual touchpad is not the desired media-input node.

Device selection implications:

- **Autodetection + exclusions:** what main currently uses; sufficient for this Dial source and for consumer nodes meeting the heuristic.
- **`linux-dev-names-include`:** exact names, not regex. In source, a matching name replaces the heuristic decision, so it can explicitly admit a transport-only node or a device named `kanata`. An exclude still wins. [`Discovery:674–717`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L674-L717).
- **`linux-dev`:** an explicit list opens only those paths, bypassing discovery, name filters, and the default `kanata` guard. Prefer stable paths over transient `eventN`; nonexistent paths enter the missing-device list. [`Selection:60–73`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L60-L73), [`opening:656–671`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L656-L671), [`syntax`](https://github.com/jtroo/kanata/blob/v1.9.0/docs/config.adoc#L3877-L3960).
- **`linux-device-detect-mode any`:** broader than a targeted media-node exception; source admits even `Other`, so it is not an attractive precision fix. [`Classification:260–305`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L260-L305).
- **`linux-continue-if-no-devs-found yes`:** useful for an absent optional device, but not a discovery override or guarantee of flawless reconnect. [`Documentation`](https://github.com/jtroo/kanata/blob/v1.9.0/docs/config.adoc#L3983-L4000).

# Ownership alternatives

## One instance directly owns the relevant devices

This is the simplest merger if device-specific mapping differences can be reconciled. Transferring Kinesis to main would require relinquishing kinata's grab and preserving its caps/F21/F22 behavior deliberately. The shared mapping would apply to **every** main-owned device producing those codes; there is no retained Linux device identity for separate keymaps here. Merely removing the main exclusion while kinata remains its owner creates competing grabs, not a merger ([`exclusive-grab calls`](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L120-L128)).

## Deliberately chain kinata into main

Upstream capability permits a scoped first-stage remapper feeding a second-stage merger. The following is a **source-supported candidate**, not an applied or live-tested change: retain kinata's existing source/layer and replace only its `defcfg` with:

```lisp
(defcfg
  process-unmapped-keys yes
  linux-dev-names-include (
    "Kinesis Freestyle Edge RGB Keyboard"
  )
  linux-continue-if-no-devs-found yes
  linux-output-device-name "kanata-kinata"
)
```

With main's present autodetection and exact physical-node exclusions, `kanata-kinata` would be eligible as a keyboard. Main would still exclude its own default output named `kanata`; kinata's allowlist admits only the physical Kinesis node, not main. This yields an acyclic ownership graph:

```text
Kinesis keyboard → kinata → kanata-kinata ─┐
Kinesis Consumer Control ─────────────────┼→ main → kanata → Umbriel
Surface Dial Virtual Keyboard/Mouse ──────┘
```

The output-name option is documented in [`v1.9.0 config:4113–4125`](https://github.com/jtroo/kanata/blob/v1.9.0/docs/config.adoc#L4113-L4125). Renaming is **not necessary** if an explicitly scoped downstream selector consumes a default-named upstream output, but all `kanata` outputs share that name, making exact-name selection ambiguous and risking self-capture. Explicit stable paths can distinguish them; path ownership/availability must be designed separately.

**Feedback guard is narrow:** only autodetection rejects the exact name `kanata` ([`guard`:260–264](https://github.com/jtroo/kanata/blob/v1.9.0/src/oskbd/linux.rs#L260-L264)). It is not a general virtual-device exclusion, creator/PID check, or graph-cycle detector. A renamed final output can be captured by its own broad discovery; explicit names/paths can bypass the guard. Keep the final output default-named or explicitly exclude it, and audit every instance's selection before considering a chain. Default-named independent instances are not implicitly chained.

# Modifier-collision tension

Single-output merging solves event placement, **not device-aware key reference counting**. Two Left Shifts on different input devices become the same coordinate. The layout removes all ordinary states at that coordinate on release ([`release`:328–343](https://github.com/jtroo/kanata/blob/v1.9.0/keyberon/src/layout.rs#L328-L343), [`dequeue`:1493–1508](https://github.com/jtroo/kanata/blob/v1.9.0/keyberon/src/layout.rs#L1493-L1508)); output deduplicates presses and emits a release when the key disappears ([`output release`:1190–1206](https://github.com/jtroo/kanata/blob/v1.9.0/src/kanata/mod.rs#L1190-L1206), [`press deduplication`:1237–1253](https://github.com/jtroo/kanata/blob/v1.9.0/src/kanata/mod.rs#L1237-L1253)).

Concrete source-derived hazard: hold physical Left Shift; the Dial emits Left Shift down, volume down/up, Left Shift up. The Dial's release can clear the merged Shift state while the physical key remains held. The daemon really sends that sequence ([`volume.rs:36–44`](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/controller/controls/volume.rs#L36-L44), [`key_click/press/release`:149–182](https://github.com/daniel5151/surface-dial-linux/blob/43dd973092871d8ef0c452b0797b519f5a9ddfac/src/fake_input.rs#L149-L182)). Right Shift uses a different coordinate and deserves a separate test. Chaining does not repair provenance already discarded upstream. The same concern applies to simultaneous identical keys on two physical keyboards.

This is **not a reproduced live bug**. It is a concrete failure mode implied by this upstream implementation, relevant before recommending consolidation as a universal modifier fix.

# Proposed test matrix — not executed

| Case | Required observation |
|---|---|
| Dial alone | Its own Shift+volume reaches the final output and invokes one intended fine action per click. |
| Main-owned keyboard Shift + plain consumer volume | Both appear on one output; verify left/right Shift and fine/coarse command selection. |
| Kinesis Shift + plain consumer volume, current split | Establish Umbriel's actual cross-keyboard modifier behavior before deciding a merger is necessary. |
| Kinesis Shift + media, candidate chain | Final output receives the chord; caps and programmed F21/F22 retain intended behavior. |
| Hold Left Shift, rotate Dial, then type a letter | Detect premature merged Shift release; repeat with Right Shift and reverse ordering. |
| Two keyboards hold the same Shift; release one | Check whether the other holder remains effective; do not assume reference counting. |
| Simultaneous volume clicks from two devices | Check loss/deduplication and repeated-action counts. |
| Restart/reconnect upstream, absent Dial | Verify registration, exclusive ownership, and downstream recovery on the actual 1.9 package. |
| All virtual outputs | Confirm an acyclic graph: no self-capture, feedback, or unexpected grabbing by another instance. |

# Cross-references and verification limits

- [`Existing diagnosis`](/design/surface-dial/diagnosis0.glm53.md): prior live evidence of Dial-injected Shift+volume passing through main and reaching fine-volume bindings. This assessment does not repeat or independently validate that probe.
- [`Media-key producer`](/media-keys.etc.pb): declares plain 0.06 steps and Shift 0.02 steps; merger capability does not replace this downstream action policy.
- [`Main playbook`](/kanata.srv.pb) and [`kinata playbook`](/kinata.srv.pb): establish declared ownership and remapping, not necessarily current deployed state.

Only repository/source reading and the non-device-opening `--version` query were performed. No service restarts, grabs, event injection, deployed-file inspection/changes, config validation run, compositor source assessment, or live failure reproduction. The candidate's syntax and selection behavior were checked against upstream documentation/source, not by launching Kanata.
