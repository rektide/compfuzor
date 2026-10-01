---
type: Research
title: "Kernel uhid short-report archaeology — exact revision history and minimal fix for the BlueTurn drop"
description: Verified commit timeline of the HID short-report regression (v7.0 memset removal → v7.1 partial restore → v7.2/7.1.4 uhid fix), the local debplus tree's exact state, the lore review thread, and a zero-fuzz cherry-pick recipe.
tags: [kernel, hid, uhid, bluetooth, hid-over-gatt, blueturn, regression, cherry-pick]
status: draft
generated: { by: agent:general, at: 2026-10-01 }
verified: { by: agent:general, at: 2026-10-01 }
sources:
  - Local git checkout /usr/local/src/linux (torvalds/linux @ v7.3-rc3-60-g587858367581) — all torvalds commits hash-verified locally
  - stable/linux linux-7.1.y and linux-7.0.y branches fetched directly over git from git.kernel.org
  - cdn.kernel.org ChangeLog-7.1.4 (release containment of the backport)
  - lore.kernel.org raw mbox of the review + regression thread (fetched 2026-10-01)
  - Live host evidence: uname, git reflog, dmesg/journalctl (2026-10-01)
---

# Kernel uhid short-report archaeology

Companion to [`blueturn-linux-research.general.md`](/design/blueturn/blueturn-linux-research.general.md)
(general background, workarounds, device mode table). This document verifies the
research doc's kernel claims against the actual local tree and live host, corrects
one significant error (the 7.1.y backport **did** ship, in **7.1.4**), and gives the
exact minimal fix for this machine's debplus kernel.

## 0. Executive summary

- The running kernel **7.1.0-debplus.1** was built on **2026-08-09 from
  `987301279ffa` = tag `v7.1` + one local commit ("amdgpu fix")** — proven by git
  reflog and by the build stamp (`KBUILD_BUILD_TIMESTAMP` = HEAD committer date,
  `2026-08-09T02:25:04-04:00`, matches `uname -a` to the second).
- v7.1 fixed short-report dropping for **usbhid and i2c-hid only**; **uhid** (the
  transport of every BT LE HID-over-GATT device, incl. the BlueTurn) still called
  legacy `hid_input_report()` with `bufsize == size`, so the core dropped the
  7-byte reports: `Event data for report 0 was too short (8 vs 7)` — reproduced
  live on this host (see [§4](#4-the-local-trees-exact-state)).
- The upstream fix (`63a694c51bf1`, v7.2) and its stable backport
  (`cfc0d283d931`) change exactly **8 lines in `drivers/hid/uhid.c`** and
  cherry-pick onto the debplus build head with **zero fuzz** — the pre-image blob
  of `uhid.c` is bit-identical (`524b53a3c87b…`) at `v7.1`, at the debplus head,
  and at both commits' parents.
- **Correction to the research doc:** `cfc0d283d931` shipped in released point
  release **v7.1.4 (2026-07-18)** — verified in stable git and in
  [cdn.kernel.org ChangeLog-7.1.4](https://cdn.kernel.org/pub/linux/kernel/v7.x/ChangeLog-7.1.4).
  The doc's "not shipped as of 7.1.13" claim is a methodology error: stable
  ChangeLogs are per-release deltas (7.1.6's log cannot contain a 7.1.4 commit),
  and the doc only checked ChangeLog-7.1.6…7.1.13.
- The user's "worked in 7.0" belief is **wrong for uhid**: v7.0 dropped short
  reports on **every** transport (`0a3fe972a7cb`). The pedal last worked on
  **≤ v6.19**. This host ran `6.19.0-dirty` and jumped **straight to 7.1.0** on
  2026-08-09 (reflog: `v6.19 → v7.1` on 08-08), skipping 7.0 entirely — which is
  why the breakage is remembered as "a 7.1 thing".

## 1. Version × transport × behavior matrix

Behavior for a device whose input report is **shorter than its report descriptor
declares** (BlueTurn: 7-byte report vs 8-byte descriptor). "pad+deliver" = the old
zero-pad-and-process behavior.

| Kernel | usbhid (USB HID) | i2c-hid (touchpads…) | uhid (BT LE HOG, **BlueTurn**) | Governing code |
|---|---|---|---|---|
| ≤ v6.19 | pad+deliver | pad+deliver | **pad+deliver ✓** | old `memset(cdata + csize, 0, rsize - csize)` in `hid_report_raw_event()` (verified at tag v6.19, `hid-core.c:2059-2062`) |
| v7.0 (incl. 7.0.1–7.0.14, EOL) | **DROP** | **DROP** | **DROP** | `0a3fe972a7cb` removes memset, `csize < rsize → -EINVAL` for all transports, no exceptions |
| v7.1.0 – v7.1.3 | pad+deliver ✓ | pad+deliver ✓ | **DROP** | `206342541fc8` + `2c85c61d1332`: core takes `bufsize`, but only usbhid/i2c-hid pass real buffer sizes; uhid still on legacy `hid_input_report()` (`bufsize == size` ⇒ `bsize < rsize` ⇒ drop) |
| **v7.1.4 – v7.1.13** (7.1.y tip, 2026-09-02) | ✓ | ✓ | **pad+deliver ✓** | backport `cfc0d283d931` (shipped 2026-07-18) |
| v7.2+ | ✓ | ✓ | **pad+deliver ✓** | `63a694c51bf1` in-tree |
| **this host: 7.1.0-debplus.1** (= `v7.1` + local amdgpu commit) | ✓ | ✓ | **DROP ✗** (live: `(8 vs 7)` in dmesg) | v7.1 code, see [§4](#4-the-local-trees-exact-state) |
| local checkout `/usr/local/src/linux` (v7.3-rc3-60) | ✓ | ✓ | ✓ (fix present at `uhid.c:598,609`) | `63a694c51bf1` present |

Two consequences worth restating:

- On the running kernel the drop happens **before** `hidraw_report_event()`, so
  hidraw listeners never see the report either (verified: the `bsize < rsize`
  bail-out precedes the `HID_CLAIMED_HIDRAW` branch in the v7.1 code, quoted in
  §4).
- There is **no quirk or module parameter** escape: the only module param in
  `hid-core.c` is `ignore_special_drivers` (`hid-core.c:45`); `uhid.c` has none;
  the size check is not quirk-gated. (Research doc claim, re-verified locally.)

## 2. What the local tree is — and what it is not

```
$ git -C /usr/local/src/linux log --oneline -5
587858367581 Merge tag 'nfsd-7.3-1' …
$ git -C /usr/local/src/linux describe --tags
v7.3-rc3-60-g587858367581
$ git remote -v
origin  https://github.com/torvalds/linux
rpi     https://github.com/raspberrypi/linux [blob:none]
```

- `/usr/local/src/linux` is a **vanilla torvalds tree at v7.3-rc3 + 60**. It is
  **not** the source of the running kernel — it was moved forward on 2026-08-24
  (reflog: `checkout: moving from v7.1 to master`, then fast-forward), long after
  the debplus.1 build on 08-09.
- The debplus build flow ([`/usr/local/src/linux-config-debplus/MAKE.sh`](/usr/local/src/linux-config-debplus/MAKE.sh))
  builds `bindeb-pkg` from **whatever HEAD is at build time**, stamping
  `SOURCE_DATE_EPOCH`/`KBUILD_BUILD_TIMESTAMP` from HEAD's committer date and
  `KDEB_PKGVERSION=7.1.0-1` by hand.
- Reflog of the checkout, reconstructing what happened:

```
05f7e89ab973 HEAD@{2026-08-08}: reset: moving to HEAD
8cd9520d35a6 HEAD@{2026-08-08}: checkout: moving from v6.19 to v7.1
8cd9520d35a6 HEAD@{2026-08-08}: checkout: moving from … to v7.1
987301279ffa HEAD@{2026-08-09}: commit: amdgpu fix
e7aa57247700 HEAD@{2026-08-24}: checkout: moving from v7.1 to master
66498c75b4f8 HEAD@{2026-08-24}: merge origin/master: Fast-forward
587858367581 HEAD@{2026-09-15}: export from jj
```

- Smoking gun tying running kernel to a commit:

```
$ git log -1 --format='%H %cI %s' 987301279ffa
987301279ffaf3a6f2eaca7ad7f4a8b7eec3008e 2026-08-09T02:25:04-04:00 amdgpu fix
$ git rev-parse v7.1 987301279ffa^     # parent == v7.1 tag
8cd9520d35a6c38db6567e97dd93b1f11f185dc6  (both)
$ uname -a
Linux workhorse … 7.1.0-debplus.1 #1 SMP PREEMPT_DYNAMIC 2026-08-09T02:25:04-04:00 …
```

`987301279ffa`'s committer date **is** the kernel's build timestamp, so the
running kernel = `v7.1` (8cd9520d35a6) + the local amdgpu patch
(4 files, `drivers/gpu/drm/amd/pm/…` only — does not touch HID).
The kernel-side amdgpu hunk is exactly the change that
[`hotfixes/amdgpu-power.sh`](/usr/local/src/linux-config-debplus/hotfixes/amdgpu-power.sh)
exists to re-apply after checkout replacements.

**Presence check in the local (v7.3-rc3-60) tree — all torvalds commits are in;
the stable backport was fetched in during this research:**

| Commit | Present in local tree? | First release containing it |
|---|---|---|
| `0a3fe972a7cb` remove memset | ✅ yes (by hash) | v7.0 |
| `206342541fc8` hid_safe_input_report() | ✅ yes | v7.1 |
| `2c85c61d1332` bufsize to hid_report_raw_event | ✅ yes | v7.1 |
| `4d3a2a466b8d` %zu format fixup | ✅ yes | v7.1 |
| `63a694c51bf1` uhid → hid_safe_input_report | ✅ yes | v7.2 |
| `cfc0d283d931` stable backport | ➕ fetched from stable/linux `linux-7.1.y` during this session (not part of torvalds history) | **v7.1.4** |

## 3. Commit archaeology (verified)

All diffs below were read from the local git object store (hash-identical to
upstream; the tree's `origin` is torvalds/linux). kernel.org's cgit web UI is
currently behind Anubis anti-bot for automated clients; the plain-git and CDN
endpoints used here are unaffected.

### 3.1 `0a3fe972a7cb` — the v7.0 regression

[HID: core: Mitigate potential OOB by removing bogus
memset()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=0a3fe972a7cb)
— Lee Jones, 2026-03-09, suggested by Benjamin Tissoires, committed to v7.0
(rc5+). Entire diff:

```diff
--- a/drivers/hid/hid-core.c
+++ b/drivers/hid/hid-core.c
@@ -2057,9 +2057,10 @@ int hid_report_raw_event(…)
 	if (csize < rsize) {
-		dbg_hid("report %d is too short, (%d < %d)\n", report->id,
-				csize, rsize);
-		memset(cdata + csize, 0, rsize - csize);
+		hid_warn_ratelimited(hid, "Event data for report %d was too short (%d vs %d)\n",
+				     report->id, rsize, csize);
+		ret = -EINVAL;
+		goto out;
 	}
```

**Why:** the memset zeroed `rsize - csize` bytes past the end of the *received*
data — but HID core had no idea how big the *allocated* buffer was, so a report
descriptor (attacker-controlled) declaring a larger size than the transport's
buffer made the kernel read/write out of bounds in the subsequent
processing. The commit message: *"as we have previously seen, doing so can easily
result in OOB reads and writes in the subsequent thread of execution"*. The
series cover letter ([lore](https://lore.kernel.org/all/20260415-wip-fix-core-v1-0-ed3c4c823175@kernel.org/),
Tissoires) elaborates: *"We only had corner cases of malicious devices exposing
the OOB because in most cases, the buffer provided by the transport layer needs
to be allocated at probe time and is large enough"*. The original posting
([RFC v3](https://lore.kernel.org/all/20260309145942.1496072-1-lee@kernel.org/))
notes the v3 delta: *v2 → v3: show a warning and return early*.

**No CVE reference exists** in the commit, the v1/v3 postings, or the series —
the motivation is generic malicious-device OOB hardening, not a specific CVE
(research doc said "find … any CVE reference": answer is *there is none*).

### 3.2 `206342541fc8` — v7.1 partial restore, usbhid + i2c-hid only

[HID: core: introduce
hid_safe_input_report()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=206342541fc8)
— Tissoires, 2026-05-04, v7.1 (rc4+). Adds `hid_safe_input_report(hid, type,
data, bufsize, size, interrupt)` and converts exactly two transports: usbhid
(`drivers/hid/usbhid/hid-core.c`) and i2c-hid
(`drivers/hid/i2c-hid/i2c-hid-core.c`). Commit message: *"hid_input_report() is
used in too many places to have a commit that doesn't cross subsystem borders…
This effectively revert[s] to the old behavior for those two transport layers."*
`Fixes: 0a3fe972a7cb`, `Cc: stable`.

### 3.3 `2c85c61d1332` — v7.1 core becomes buffer-size-aware

[HID: pass the buffer size to hid_report_raw_event](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2c85c61d1332)
— Tissoires, 2026-05-04 (same series), v7.1. `hid_report_raw_event()` gains a
`bufsize` parameter and splits the old check in two:

```c
if (bsize < rsize)  → drop, warn "Event data for report %d was too short (%d vs %zu)" (buffer genuinely too small)
if (csize < rsize)  → dbg + memset zero-pad, deliver (data short but buffer big enough)
```

Legacy `hid_input_report()` callers pass `bufsize == size`, so for them the new
`bsize < rsize` check is **exactly** as strict as v7.0's — i.e. v7.1 changed
nothing for uhid. Also updates the HID-BPF dispatcher and a handful of in-tree
`raw_event` callers. `4d3a2a466b8d` (Nathan Chancellor, 2026-05-17, v7.1) is the
follow-up fixing the `%ld` → `%zu` specifier for 32-bit builds — last commit to
touch the drop-site hunk before the 7.2-era state.

### 3.4 `63a694c51bf1` — the v7.2 uhid fix (upstream)

[HID: uhid: convert to hid_safe_input_report()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=63a694c51bf1)
— Carlos Llamas, 2026-06-06, v7.2 (rc1+), `Fixes: 0a3fe972a7cb`, `Closes:`
the lore thread below. Full diff is 8 lines in `drivers/hid/uhid.c`
(`uhid_dev_input` + `uhid_dev_input2`), quoted in [§6](#6-minimal-fix-recipe).

### 3.5 `cfc0d283d931` — the 7.1.y backport (shipped in v7.1.4)

[stable commit](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=cfc0d283d931)
— same author/date, "commit 63a694c51bf1 upstream", identical diff. Verified in
the fetched `linux-7.1.y` branch: committed 2026-07-18T16:55:33+02:00, and
`git merge-base --is-ancestor` shows it inside release commit `7a5cef0db479`
("Linux 7.1.4", 2026-07-18T16:55:52+02:00) — and independently confirmed in
[cdn.kernel.org ChangeLog-7.1.4](https://cdn.kernel.org/pub/linux/kernel/v7.x/ChangeLog-7.1.4).
The 7.1.y branch tip is 7.1.13 (2026-09-02), which contains it.

### 3.6 `linux-7.0.y` — never fixed, EOL

Fetched `linux-7.0.y`: tip = `458c6079fc1d` "Linux 7.0.14" (2026-06-27). No uhid
fix on the branch — it EOL'd three weeks *before* `cfc0d283d931` was even
backported. (Research doc's "v7.0.x ≤ 7.0.14: no fix" — confirmed correct.)

### 3.7 Discrepancies vs the research doc

| Research doc claim | Verdict |
|---|---|
| §1.3 timeline: commits, dates, authors, first-release containment (0a3fe→7.0, 2063/2c85→7.1, 63a6→7.2) | ✅ all confirmed by hash in local tree + `git tag --contains` |
| §1.4 "as of 7.1.13 it has **not** shipped in a released point release… expect it in the next point release" | ❌ **wrong** — shipped in **v7.1.4** (2026-07-18), three months before the doc was written. Root cause of their error: stable ChangeLogs are per-release deltas; they only checked ChangeLog-7.1.6…7.1.13, which cannot contain a 7.1.4 commit |
| §1.3 "(8 vs 7) shape consistent with either v7.0 or v7.1" | ✅ (v7.0 prints `(rsize, csize)`, v7.1 prints `(rsize, bsize)`, `bsize == csize` for legacy callers — same rendered text on x86-64) |
| §1.4 "uhid calls legacy hid_input_report through v7.1" | ✅ `git show v7.1:drivers/hid/uhid.c` lines 598/609 |
| §2.5 "hidraw never sees the dropped report on 7.0/7.1" | ✅ drop precedes the `HID_CLAIMED_HIDRAW` branch (code order, §4 below) |
| §1.5 "no quirk/module parameter avoids the drop" | ✅ only `ignore_special_drivers` (`hid-core.c:45`); nothing in `uhid.c` |

## 4. The local tree's exact state

### 4.1 What is running (v7.1 + amdgpu, the broken build)

`git show v7.1:drivers/hid/hid-core.c`, the report-entry path (v7.1 file,
≈ lines 2075–2098; identical in the debplus build since the amdgpu commit touches
only `drivers/gpu/drm/amd/pm/`):

```c
	if (bsize < rsize) {
		hid_warn_ratelimited(hid, "Event data for report %d was too short (%d vs %zu)\n",
				     report->id, rsize, bsize);
		return -EINVAL;                       /* <-- BlueTurn reports die here */
	}

	if (csize < rsize) {
		dbg_hid("report %d is too short, (%d < %d)\n", report->id,
			csize, rsize);
		memset(cdata + csize, 0, rsize - csize);   /* zero-pad… unreachable for uhid */
	}

	if ((hid->claimed & HID_CLAIMED_HIDDEV) && hid->hiddev_report_event)   /* hidraw: after the drop */
		...
```

`git show v7.1:drivers/hid/uhid.c` lines 595–612 — uhid still on the legacy API,
so `bufsize == size == 7 < rsize == 8`:

```c
	hid_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input.data,
			 min_t(size_t, ev->u.input.size, UHID_DATA_MAX), 0);   /* line 598 */
	...
	hid_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input2.data,
			 min_t(size_t, ev->u.input2.size, UHID_DATA_MAX), 0);   /* line 609 */
```

Live evidence on this host (2026-09-30/10-01):

```
kernel: input: iRig BlueTurn Keyboard as /devices/virtual/misc/uhid/0005:0214:0002.003C/input/input160
kernel: hid-generic 0005:0214:0002.003C: input,hidraw10: BLUETOOTH HID v0.01 Keyboard [iRig BlueTurn] …
[3125850.841804] hid-generic 0005:0214:0002.0042: Event data for report 0 was too short (8 vs 7)
```

The `/devices/virtual/misc/uhid/` path is direct proof the reports come through
**uhid** (BlueZ HOG → `/dev/uhid`), not usbhid/i2c — which is precisely why the
7.1 partial restore didn't help.

### 4.2 The current checkout (v7.3-rc3-60) — already fixed

`drivers/hid/hid-core.c` now (lines 2043–2119): `hid_report_raw_event(…, size_t
bufsize, u32 size, …)` with the two-tier check above; `hid_input_report()`
documented as *"Legacy, please use hid_safe_input_report() instead"* (line 2198);
`hid_safe_input_report()` at 2224. Last commits to touch the drop hunk, from
`git log -L 2088,2098:drivers/hid/hid-core.c`: `4d3a2a466b8d` (format specifier)
← `2c85c61d1332` (introduced the bsize/csize split) ← `0a3fe972a7cb` (introduced
the drop) ← `85cdaf524b7d` (2006-era "HID: make a bus from hid code", the original
zero-pad).

`drivers/hid/uhid.c` lines 598–610 — the fix is present:

```c
	hid_safe_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input.data, UHID_DATA_MAX,
			      min_t(size_t, ev->u.input.size, UHID_DATA_MAX), 0);
	...
	hid_safe_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input2.data, UHID_DATA_MAX,
			      min_t(size_t, ev->u.input2.size, UHID_DATA_MAX), 0);
```

So **rebuilding debplus from the current HEAD would fix the pedal with no patch
at all** — that's the alternative path in §6.

## 5. The lore discussion (fetched, quoted, cited)

Thread root: Benjamin Tissoires' 4-patch series
["HID: Proper fix for OOM in hid-core"](https://lore.kernel.org/all/20260415-wip-fix-core-v1-0-ed3c4c823175@kernel.org/)
(2026-04-15, `<20260415-wip-fix-core-v1-0-ed3c4c823175@kernel.org>`), whose
patches 1–2 became `2c85c61d1332`/`206342541fc8`. Cover letter: the memset
removal *"enforced the spec a little bit more [and] introduced both regressions
for devices not following the spec (not necessar[il]y malicious), but also a
stream of errors for those devices"*; the API change is confined to the two
transport callers because *"we have too many callers in various subsystems. We
can switch them one by one to the safe approach when needed."*

The cited regression message (the one in the uhid commit's `Closes:` tag):
[Carlos Llamas, 2026-05-30](https://lore.kernel.org/all/ahsh0UtTX6e0ZeHa@google.com/)
(`<ahsh0UtTX6e0ZeHa@google.com>`), "Re: [PATCH 2/4] HID: core: introduce
hid_safe_input_report()". It contains two key moments:

1. Tissoires (2026-04-16, quoted in that message) explaining why the series did
   **not** convert uhid: *"it's not entirely deprecated because, for instance, in
   uhid we only have the buffer with the provided size around. So we can't be
   less restrictive in that precise case, and then switching to _safe will not
   change a bit."*
2. Llamas' correction, which became the fix: *"our CI started failing with
   commit 0a3fe972a7cb… However, I just realized our call path goes through uhid
   precisely, which still triggers the EINVAL error since uhid [was] not
   converted… My vague understanding though, is that uhid_event uses a static
   buffer in ev->data[UHID_DATA_MAX], so maybe we can use that through
   uhid_dev_input{2}()? I ran the following path through our CI and it fixed our
   issue"* — followed by the exact 8-line diff that landed as `63a694c51bf1`
   (upstream, v7.2) and `cfc0d283d931` (7.1.y, v7.1.4). Tissoires' assumption was
   wrong because `ev->u.input{,2}.data` is a fixed `UHID_DATA_MAX` (4096-byte)
   member of the uhid event struct
   ([`include/uapi/linux/uhid.h:68,78,82`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/uapi/linux/uhid.h)),
   so the *allocated* buffer size genuinely is known — it just wasn't being
   passed down. (Patchwork shows the formal submission
   [v1](https://patchwork.kernel.org/project/linux-input/patch/20260606181552.3095967-1-cmllamas@google.com/)
   `<20260606181552.3095967-1-cmllamas@google.com>`, later superseded by the
   committed version.)

Also part of the trail: the original memset-removal postings
([v1](https://lore.kernel.org/all/20260227163031.1166560-1-lee@kernel.org/)
2026-02-27, [RFC v3](https://lore.kernel.org/all/20260309145942.1496072-1-lee@kernel.org/)
2026-03-09 — v3 is the committed text; its cover question "return SUCCESS or
-EINVAL?" was answered `-EINVAL` by Tissoires during applying).

## 6. Minimal fix recipe

### Cleanliness proof

```
blob(drivers/hid/uhid.c @ v7.1)              = 524b53a3c87b3c023d05c334470bbef1a16cdb37
blob(… @ 987301279ffa  = debplus.1 head)     = 524b53a3c87b3c023d05c334470bbef1a16cdb37
blob(… @ cfc0d283d931^  = backport parent)   = 524b53a3c87b3c023d05c334470bbef1a16cdb37
blob(… @ 63a694c51bf1^  = upstream parent)   = 524b53a3c87b3c023d05c334470bbef1a16cdb37
```

All four are the same object ⇒ both commits apply to the debplus base with
**zero context drift**; neither touches any file the local amdgpu commit touched.

### Option A (recommended): rebuild 7.1.0-2 debplus with the backport

Stays on the known-good 7.1 base + amdgpu fix; matches the flow already
documented in [`DEBIAN.md`](/usr/local/src/linux-config-debplus/DEBIAN.md)
("7.1.0-2 / -debplus.2"). The backport object is already fetched into
`/usr/local/src/linux` (this session fetched `linux-7.1.y`).

```sh
cd /usr/local/src/linux

# 1. rebuild the exact debplus.1 base + fix, on a dated branch
git switch -c uhid-shortreport-20261001 987301279ffa   # v7.1 + amdgpu fix
git cherry-pick cfc0d283d931        # stable backport; or 63a694c51bf1 (identical diff)

# 2. build (per linux-config-debplus; only the version strings change)
cp /usr/local/src/linux-config-debplus/config-debian-plus .config
cd /usr/local/src/linux-config-debplus && ./MAKE.sh     # bump LOCALVERSION=-debplus.2, KDEB_PKGVERSION=7.1.0-2 first
# → linux-image-7.1.0-debplus.2_7.1.0-2_amd64.deb

# 3. install & verify
sudo dpkg -i /usr/local/src/linux-image-7.1.0-debplus.2_7.1.0-2_amd64.deb
#    reboot, then: pedal press should produce evtest events and no
#    "was too short" in dmesg (a dbg_hid line only with dyndbg enabled)
```

Caveats: after `git switch`, the *current* v7.3-rc3-60 checkout is left behind on
its own branch — switch back with `git switch master` when done (or do the build
from a [worktree](https://git-scm.com/docs/git-worktree) to leave HEAD alone).
Also note `MAKE.sh` stamps the package from `HEAD` — building from
`987301279ffa` + cherry-pick keeps the 7.1.0 version string honest.

### Option B: rebuild from current HEAD (v7.3-rc3-60)

The checkout already contains `63a694c51bf1` (and ~10 weeks of other changes).
No cherry-pick, but: re-apply the amdgpu power change via
`hotfixes/amdgpu-power.sh` (the local commit `987301279ffa` is **not** in
master), re-check `config-debian-plus` against 7.3 (`olddefconfig`), and expect a
bigger regression surface than an 8-line fix. Treat as "upgrade", not "fix".

### Option C: minimal hand-patch (no git history changes)

Apply exactly this to `drivers/hid/uhid.c` of the 7.1 base (lines 598–599 and
609–610) — verbatim the `cfc0d283d931` diff:

```diff
--- a/drivers/hid/uhid.c
+++ b/drivers/hid/uhid.c
@@ -595,8 +595,8 @@ static int uhid_dev_input(struct uhid_device *uhid, struct uhid_event *ev)
-	hid_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input.data,
-			 min_t(size_t, ev->u.input.size, UHID_DATA_MAX), 0);
+	hid_safe_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input.data, UHID_DATA_MAX,
+			      min_t(size_t, ev->u.input.size, UHID_DATA_MAX), 0);
@@ -606,8 +606,8 @@ static int uhid_dev_input2(struct uhid_device *uhid, struct uhid_event *ev)
-	hid_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input2.data,
-			 min_t(size_t, ev->u.input2.size, UHID_DATA_MAX), 0);
+	hid_safe_input_report(uhid->hid, HID_INPUT_REPORT, ev->u.input2.data, UHID_DATA_MAX,
+			      min_t(size_t, ev->u.input2.size, UHID_DATA_MAX), 0);
```

(`hid_safe_input_report()` already exists in v7.1 via `206342541fc8`; no
include/prototype changes needed.)

### No-rebuild mitigations

Unchanged from the research doc §2: HID-BPF pad/rdesc fix (udev-hid-bpf is even
checked out at `/usr/local/src/udev-hid-bpf-git`), or ≤6.19 kernel. hidraw
readers cannot see the dropped reports on this kernel (§1).

## References

- Upstream commits (torvalds):
  [`0a3fe972a7cb`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=0a3fe972a7cb) ·
  [`206342541fc8`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=206342541fc8) ·
  [`2c85c61d1332`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2c85c61d1332) ·
  [`4d3a2a466b8d`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=4d3a2a466b8d) ·
  [`63a694c51bf1`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=63a694c51bf1)
- Stable: [`cfc0d283d931` (linux-7.1.y)](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=cfc0d283d931) ·
  [ChangeLog-7.1.4](https://cdn.kernel.org/pub/linux/kernel/v7.x/ChangeLog-7.1.4)
- lore: [regression report & uhid fix proposal (Closes: tag)](https://lore.kernel.org/all/ahsh0UtTX6e0ZeHa@google.com/) ·
  [series cover "HID: Proper fix for OOM in hid-core"](https://lore.kernel.org/all/20260415-wip-fix-core-v1-0-ed3c4c823175@kernel.org/) ·
  [memset-removal RFC v3](https://lore.kernel.org/all/20260309145942.1496072-1-lee@kernel.org/)
- Local: [`/usr/local/src/linux`](/usr/local/src/linux) (torvalds @ v7.3-rc3-60;
  fetched `linux-7.1.y`/`linux-7.0.y`) ·
  [`/usr/local/src/linux-config-debplus/`](/usr/local/src/linux-config-debplus) (MAKE.sh, DEBIAN.md, hotfixes) ·
  debplus.1 build head `987301279ffa` (v7.1 + "amdgpu fix")
- Prior art in this directory: [`blueturn-linux-research.general.md`](/design/blueturn/blueturn-linux-research.general.md)
