---
type: Research
title: iRig BlueTurn on Linux — dropped input reports, workarounds, mode table, connection stability
description: Why the kernel drops BlueTurn HID reports ("Event data for report 0 was too short (8 vs 7)"), the exact commit timeline, workarounds, the official mode table, and BLE drop guidance.
tags: [bluetooth, hid, hid-over-gatt, uhid, bluez, blueturn, kernel]
status: draft
generated: { by: agent:general, at: 2026-10-01 }
sources:
  - Linux kernel source (torvalds/linux), v5.15 … v7.2 + master
  - IK Multimedia iRig BlueTurn User Manual (official PDF)
  - lore.kernel.org, BlueZ source, distro forums
---

# iRig BlueTurn on Linux — research

Situation: an iRig BlueTurn BLE foot pedal (enumerates as `iRig BlueTurn Keyboard`,
`hid-generic 0005:0214:0002.…`, bus `0005` = Bluetooth) pairs fine but every pedal
press is dropped by the kernel with:

```
hid-generic 0005:0214:0002.00XX: Event data for report 0 was too short (8 vs 7)
```

Research questions: (1) root cause of the drop, (2) workarounds, (3) the device's
mode/key table, (4) connection/bonding stability on Linux.

## 1. Why the kernel drops the reports

### 1.1 It is not BlueTurn-specific — it is a v7.0 HID-core regression for short reports

The message comes from `hid_report_raw_event()` in
[`drivers/hid/hid-core.c`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hid/hid-core.c)
(the function reached from `hid_input_report()`, the data entry point for all HID
transport drivers). In v7.0 it reads:

```c
rsize = hid_compute_report_size(report);          /* size demanded by the report descriptor */

if (csize < rsize) {
        hid_warn_ratelimited(hid, "Event data for report %d was too short (%d vs %d)\n",
                             report->id, rsize, csize);
        ret = -EINVAL;
        goto out;                                 /* <-- report dropped entirely */
}
```

v7.0, `drivers/hid/hid-core.c` ~line 2059. `rsize` = size computed from the device's
report descriptor (8 bytes for the BlueTurn's keyboard input report — classic
modifier + reserved + 6 key slots), `csize` = bytes actually delivered (7). Any
device whose input reports are shorter than its descriptor declares gets **every
report dropped** — hidraw and evdev never see it, because the bail-out happens
*before* `hidraw_report_event()` and `hid_process_report()` are called.

### 1.2 Historical behavior: short reports used to be zero-padded and processed

From the 2.6 era through v6.19, the same function deliberately tolerated short
reports:

```c
if (csize < rsize) {
        dbg_hid("report %d is too short, (%d < %d)\n", report->id, csize, rsize);
        memset(cdata + csize, 0, rsize - csize);   /* zero-pad the tail, carry on */
}
```

(verified in the v5.15, v6.1, v6.6, v6.12, v6.19 tags). A 7-byte report against an
8-byte descriptor was padded with a trailing zero and delivered — which is why this
class of slightly-noncompliant device "just worked" for ~two decades and only broke
recently.

### 1.3 Commit timeline (verified against torvalds/linux tags and patches)

| When | Commit | Effect |
|---|---|---|
| ≤ v6.19 (2026-02-08) | — | short reports zero-padded and delivered |
| **v7.0** (2026-04-12) | [`0a3fe972a7cb`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=0a3fe972a7cb) "HID: core: Mitigate potential OOB by removing bogus memset()" (Lee Jones, suggested by Benjamin Tissoires) | **removed the memset and hard-dropped short reports** (`ret = -EINVAL`), adding the exact warning seen in dmesg. The memset could read/write out of bounds because the core didn't know the allocated buffer size. |
| v7.1 (2026-06-14) | [`206342541fc8`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=206342541fc8) "HID: core: introduce hid_safe_input_report()" | new API passing the allocated buffer size; restores old zero-pad behavior **for usbhid and i2c-hid only**. |
| v7.1 | [`2c85c61d1332`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2c85c61d1332) "HID: pass the buffer size to hid_report_raw_event" | core now distinguishes "buffer genuinely too small" (drop, message "was too short (rsize vs bsize)") from "data short but buffer big enough" (zero-pad, deliver). Legacy `hid_input_report()` callers pass `bufsize == size`. |
| v7.1 | [`4d3a2a466b8d`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=4d3a2a466b8d) | format-specifier fixup; message stays "(8 vs 7)" shaped. |
| **v7.2** (2026-08-16) | [`63a694c51bf1`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=63a694c51bf1) "HID: uhid: convert to hid_safe_input_report()" (Carlos Llamas) | **uhid now passes `UHID_DATA_MAX` as the buffer size — short reports are zero-padded and delivered again.** Commit message explicitly cites the regressions ([lore thread](https://lore.kernel.org/all/ahsh0UtTX6e0ZeHa@google.com/)). |

The user-visible message is identical in shape on v7.0 (`(rsize, csize)`) and v7.1
(`(rsize, bsize)` with `bsize == csize` for uhid), so "(8 vs 7)" is consistent with
either.

### 1.4 Why the BlueTurn hits it: the uhid path (BT LE HID-over-GATT)

The BlueTurn is a Bluetooth LE HID-over-GATT (HOG) device. On Linux, BlueZ's HOG
plugin ([`profiles/input/hog.c`](https://github.com/bluez/bluez/blob/master/profiles/input/hog.c))
terminates the GATT connection in userspace and re-injects each Report
characteristic notification into the kernel through
[`/dev/uhid`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hid/uhid.c)
(UHID_INPUT2 events), tagging the device with bus `0005` (Bluetooth) and the IDs
advertised by the device's PnP characteristic (hence `0005:0214:0002`). Through
v7.1 the uhid driver called the legacy `hid_input_report()` with
`bufsize == size`, so a 7-byte notification could never be zero-padded — every BT
LE HID device that truncates its reports the same way regressed together. This is
a general HID-over-GATT/BT-LE regression, not a BlueTurn quirk. (A second
high-profile victim of the same v7.0 commit, fixed differently: Surface IPTS
touchscreens — see [`scphyle/ipts-surface-fix`](https://github.com/scphyle/ipts-surface-fix),
whose README quotes the identical message shape "Event data for report 65 was too
short (7491 vs 7488)".)

Practical kernel guidance:

- **v7.2 or newer: fixed** (uhid zero-pads).
- **v7.1.x stable:** the fix is cherry-picked onto the `linux-7.1.y` branch as
  [`cfc0d283d931`](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=cfc0d283d931)
  (committed 2026-07-18), but as of 7.1.13 it has **not** shipped in a released
  point release (checked ChangeLog-7.1.6 … 7.1.13 on
  [cdn.kernel.org](https://cdn.kernel.org/pub/linux/kernel/v7.x/)) — expect it in
  the next point release; verify the ChangeLog before counting on it.
- **v7.0.x stable (≤ 7.0.14): no fix** on the branch.
- **≤ v6.19: unaffected** (old zero-pad behavior).

### 1.5 No quirk or module parameter avoids the drop

Verified in-tree: the `hid` module's only parameter is
`module_param_named(ignore_special_drivers, …)`, and the `HID_QUIRK_*` list in
[`include/linux/hid.h`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/include/linux/hid.h)
(IGNORE, NOGET, BADPAD, MULTI_INPUT, …) contains nothing that relaxes the report
size check. The check is not quirk-gated. The only in-kernel escape hatches are a
newer kernel or HID-BPF (below).

## 2. Workarounds

Ranked by practicality:

1. **Run kernel ≥ v7.2** (or a `linux-7.1.y` build containing `cfc0d283d931` once
   released). This is the actual upstream fix; nothing else is needed — reports are
   zero-padded and evdev works as before.

2. **Stay on / boot ≤ v6.19** for sessions using the pedal. Same effect via the
   old code path.

3. **HID-BPF** (kernel ≥ 6.3, no rebuild needed): load a BPF program that either
   pads the incoming event to 8 bytes in the `hid_bpf_device_event` hook or rewrites
   the report descriptor via `rdesc_fixup` so the declared size matches reality.
   Infrastructure:
   - [`udev-hid-bpf`](https://gitlab.freedesktop.org/libevdev/udev-hid-bpf) — udev-based
     loader for per-device HID-BPF fixes, with a
     [tutorial](https://libevdev.pages.freedesktop.org/udev-hid-bpf/tutorial.html).
   - [`hid-tools`](https://gitlab.freedesktop.org/libevdev/hid-tools) — `hid-decode`
     (dump/interpret the report descriptor) and `hid-recorder` (capture reports).
   - Kernel docs: [`Documentation/hid/bpf.rst`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/hid/bpf.rst).
   **Caveat:** know *which* byte is missing before padding. If the BlueTurn simply
   truncates trailing zero key slots (7 = 8 minus one trailing `0x00` key),
   appending a zero byte is exactly right. If it omits the reserved byte after the
   modifier, the pad must be *inserted* at offset 1 or keys decode wrong. Dump the
   descriptor (`hid-decode < /sys/class/hidraw/hidrawN/device/rdesc`) and watch a
   real press (`btmon`, or `hid-recorder` on a ≤6.19 kernel) to decide.

4. **Userspace GATT reader + uinput shim** (bypasses the kernel HID stack
   entirely): BlueZ exposes the Report characteristic on the D-Bus GATT API, so a
   small daemon can `StartNotify` on it (alongside bluetoothd, which keeps the
   connection), decode the boot-keyboard bytes (byte 0 = modifiers, bytes 1–6/2–7 =
   keycodes) and emit keys through `/dev/uinput`. Libraries: `bleak` (Python) or
   plain D-Bus. This works on any kernel but duplicates what HOG already does.
   `btmon` is the quickest way to see the raw 7-byte notifications. No existing
   BlueTurn-specific project was found on GitHub; analogous projects:
   [`fanhong-li/hidrelay`](https://github.com/fanhong-li/hidrelay) (remaps HID page
   turner reports into virtual keys, macOS),
   [`Lmd64-zz/AirturnPedalInput`](https://github.com/Lmd64-zz/AirturnPedalInput)
   (AirTurn BT-105 over CoreBluetooth),
   [`tibo-develop/remarkable-paper-pro-airturn`](https://github.com/tibo-develop/remarkable-paper-pro-airturn)
   (AirTurn DUO on reMarkable, translates HID keys to touch gestures).

5. **hidraw userspace reader — NOT a workaround on v7.0/v7.1.** The
   `bsize/csize < rsize` bail-out runs *before* `hidraw_report_event()`, so on the
   affected kernels hidraw never receives the dropped report either. On fixed
   kernels (≥7.2 / ≤6.19) hidraw is the natural interface for custom remapping
   of a working device.

BlueZ itself offers no knob for this: for LE HOG devices BlueZ always goes through
uhid (`UserspaceHID` in
[`profiles/input/input.conf`](https://github.com/bluez/bluez/blob/master/profiles/input/input.conf)
selects uhid vs kernel HIDP for *classic* HID only), and no bluetoothd setting
changes report lengths.

## 3. BlueTurn mode table (official, from the IK Multimedia User Manual)

Source: [iRig BlueTurn User Manual (PDF)](https://g1.ikmultimedia.com/html/Manuals/iRigBlueTurn/iRig-BlueTurn_User_Manual.pdf)
("iRig BlueTurn modes", pp. 6–9; product page:
[ikmultimedia.com/products/irigblueturn](https://www.ikmultimedia.com/products/irigblueturn/)).

**Mode selection happens only at power-on.** Hold any one foot switch while
flipping the power switch ON → both foot-switch LEDs blink → press a switch to
choose the mode → the Bluetooth LED blinks and the unit is discoverable/pairable
for 30 seconds:

| Selection (while LEDs blink) | Mode | Left pedal | Right pedal | Intended target |
|---|---|---|---|---|
| Press **left** switch | Mode 1 | **Up arrow** | **Down arrow** | "most common MODE for all iOS and Android APPS" |
| Press **right** switch | Mode 2 | **Page Up** | **Page Down** | "primarily for MAC document applications such as MS Word, Powerpoint, Acrobat" |
| Press **both** switches | Mode 3 | **Left arrow** | **Right arrow** | (presenter-style navigation) |

Notes from the same manual:

- Plain power-on (no switch held) re-boots into the **last used mode**.
- There is **no short/long-press distinction per pedal**; each pedal sends exactly
  one key per press. The only long-press behavior: with the cursor in an iOS text
  box, holding the **left** pedal (the "up arrow" of Mode 1) for ≥ 3 seconds
  toggles the iOS virtual keyboard on/off.
- "Modes have pre-assigned HID messages … The associations can't be edited."
- Holding **both** foot switches *while flipping power on* (before the selection
  state) boots the **bootloader** (firmware updates only) — distinct from Mode 3
  selection.
- Status LED: flashing = waiting to pair (enters sleep after 30 s unpaired; cycle
  power to retry), solid = connected, brief fast flashes = low batteries. BLE 4.1,
  ~10 m range, 2×AAA.

For Linux use, Mode 2 (Page Up/Down) or Mode 1 (Up/Down) are the useful ones;
Mode 3 gives Left/Right arrows.

## 4. Connection drops / bonding flakiness on Linux

Searches (DuckDuckGo, GitHub, IK/OnSong/unrealBook resources) found **no published
BlueTurn-specific Linux reports of silent bearer death or bonding flakiness** — the
device is old (2016-era), low-volume, and most users are on iOS. So the following
is the general BLE-HID-on-Linux playbook, all of it applicable to a pedal that
drops minutes after connecting:

- **BlueZ input plugin idle timeout**: `IdleTimeout` in
  [`/etc/bluetooth/input.conf`](https://github.com/bluez/bluez/blob/master/profiles/input/input.conf)
  disconnects idle HID sessions; current BlueZ defaults to `0` (disabled) but some
  distros ship a non-zero value — set `IdleTimeout=0`.
- **Reconnect/availability tuning** in `/etc/bluetooth/main.conf`:
  `ReconnectAttempts=7`, `ReconnectIntervals=1,2,4,8,16,32,64`,
  `FastConnectable=true`, `AutoEnable=true` — see the worked example in
  [`DasBen`'s idle-disconnect gist](https://gist.github.com/DasBen/6a3f2df8f34d674c955ea7bd143b9c12)
  (Framework 13 / MT7925 / Logitech keyboard).
- **Controller USB autosuspend** is the classic "dies a few minutes after
  connect" cause for BT keyboards: the btusb device suspends and misses
  notifications. Disable with `btusb.enable_autosuspend=0` (module param) or
  `usbcore.autosuspend=-1`, or a udev rule pinning `power/control` to `on` for the
  adapter. Widely reported, e.g.
  [askubuntu 1264315](https://askubuntu.com/questions/1264315/bluetooth-keyboard-and-mouse-disconnect-when-idle-for-a-few-seconds-and-reconnec).
- **Stale bonding cache**: remove `/var/lib/bluetooth/<adapter-MAC>/<device-MAC>/`
  and re-pair; mismatched LTKs after re-flashing produce repeated
  connect/disconnect loops (see
  [archlinux BBS 303176](https://bbs.archlinux.org/viewtopic.php?id=303176)).
- **Who is dropping whom?** Run `btmon` while it dies: a local `Disconnect Reason`
  points at BlueZ/input.conf; `HCI Disconnection Complete` with
  supervision-timeout reason points at the link/device side (range, interference,
  device sleep). The BlueTurn itself gives up and hides 30 s after power-on if
  nothing pairs, and its manual notes battery state affects behavior.
- **Controller firmware/driver quality** matters: Intel/Realtek/MediaTek (MT7925)
  BT radios each have long tails of power-management bugs
  ([level1techs MT7925 thread](https://forum.level1techs.com/t/bluetooth-issues-with-mediatek-mt7925-controller-on-linux/244440));
  updating linux-firmware + kernel is part of the fix.
- No device firmware update mechanism is documented for end users; the bootloader
  mode exists ("only needed for firmware updates") but IK has published no
  user-installable update.

## Conclusions

- The dropped reports are a **generic Linux v7.0 HID-core regression** for devices
  that send input reports shorter than their descriptors declare; the uhid
  transport (all BT LE HID-over-GATT devices, including the BlueTurn) remained
  affected through v7.1. **Fixed in v7.2** (`63a694c51bf1`), backport pending on
  the 7.1.y stable branch (`cfc0d283d931`).
- Best workaround: **kernel ≥ 7.2**. On stuck kernels, a HID-BPF pad/rdesc fix
  via udev-hid-bpf is the clean local mitigation; a D-Bus GATT + uinput shim is
  the kernel-independent fallback. hidraw readers cannot see the dropped reports
  on 7.0/7.1.
- The BlueTurn has **three fixed modes** (arrows / page keys / left-right),
  selected only at power-on; there is no per-pedal long-press except the iOS
  virtual-keyboard toggle (hold Mode-1 left pedal 3 s).
- No BlueTurn-specific Linux connectivity reports exist; the usual BLE-HID
  guidance (IdleTimeout=0, autosuspend off, reconnect tuning, cache purge,
  btmon triage) applies.

## References

- Kernel source & commits (torvalds/linux, verified 2026-10-01):
  - `drivers/hid/hid-core.c`, `hid_report_raw_event()` — [tree](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hid/hid-core.c)
  - [0a3fe972a7cb — Mitigate potential OOB by removing bogus memset()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=0a3fe972a7cb)
  - [206342541fc8 — introduce hid_safe_input_report()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=206342541fc8)
  - [2c85c61d1332 — pass the buffer size to hid_report_raw_event](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=2c85c61d1332)
  - [63a694c51bf1 — HID: uhid: convert to hid_safe_input_report()](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=63a694c51bf1)
  - [lore: hid_safe_input_report() review + regression report](https://lore.kernel.org/all/ahsh0UtTX6e0ZeHa@google.com/)
  - [drivers/hid/uhid.c](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/drivers/hid/uhid.c),
    [Documentation/hid/bpf.rst](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/tree/Documentation/hid/bpf.rst)
- BlueZ: [profiles/input/hog.c](https://github.com/bluez/bluez/blob/master/profiles/input/hog.c),
  [profiles/input/input.conf](https://github.com/bluez/bluez/blob/master/profiles/input/input.conf)
- HID-BPF tooling: [udev-hid-bpf](https://gitlab.freedesktop.org/libevdev/udev-hid-bpf),
  [hid-tools](https://gitlab.freedesktop.org/libevdev/hid-tools)
- IK Multimedia: [BlueTurn product/manuals page](https://www.ikmultimedia.com/products/irigblueturn/index.php?p=manuals),
  [User Manual PDF](https://g1.ikmultimedia.com/html/Manuals/iRigBlueTurn/iRig-BlueTurn_User_Manual.pdf)
- Related victims/projects: [scphyle/ipts-surface-fix](https://github.com/scphyle/ipts-surface-fix),
  [fanhong-li/hidrelay](https://github.com/fanhong-li/hidrelay),
  [DasBen bluetooth idle-disconnect gist](https://gist.github.com/DasBen/6a3f2df8f34d674c955ea7bd143b9c12),
  [archlinux BBS: BLE keyboard after kernel update](https://bbs.archlinux.org/viewtopic.php?id=303176),
  [askubuntu: BT keyboard idle disconnect](https://askubuntu.com/questions/1264315/bluetooth-keyboard-and-mouse-disconnect-when-idle-for-a-few-seconds-and-reconnec)
