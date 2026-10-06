# SMU power-limit API timeline: what broke the `amdgpu.ignore_min_pcap` patch

Wave file for the linux-debplus topic. Written by glm53f (GLM-5.3 Flash) on 2026-10-05.

## Situation and method

`files/linux-config-debplus/hotfixes/amdgpu-power.sh` carries a four-file patch adding an
`amdgpu.ignore_min_pcap` module parameter. The 7.1-era version hooked
`smu_get_power_limit()`/`smu_set_power_limit()` and the scalar
`smu->min_power_limit`/`max_power_limit`/`current_power_limit` fields; the current 7.3-era
version hooks `smu_get_ppt_limit()`/`smu_set_ppt_limit()` and the two-dimensional
`smu->ppt_limits.range[power_source][limit_type]` cache with `supported_mask`. On a
v7.3-rc3-60 tree the old patch failed on exactly two hunks: `amdgpu_drv.c` around line 149
and `amdgpu_smu.c` around line 2987. This document is the bisect of the upstream changes
responsible, so the hotfix can state precisely which kernels each version applies to and the
parent can size the severity of the break.

All work was read-only git archaeology (`git log`, `git show`, `git tag --contains`,
`git diff`, `git grep`) in a torvalds/linux clone with tags through v7.3-rc5 and tip
`551c722f40809618230001baccf219193e22fc5a`. Nothing in that clone was modified. First
containing tags below come from `git tag --contains <sha> --sort=version:refname`, earliest
listed. Note the clone also has a local branch named `v7.1`, which makes the bare refname
ambiguous; all ranges here were pinned with `refs/tags/…`.

## Commit table

| Commit | Subject | Author | Date | First tag |
|---|---|---|---|---|
| [`719f83f3c675`](https://github.com/torvalds/linux/commit/719f83f3c67541b1392fb45851fb8ca7716dbde9) | drm/amd/pm: drop unused smu pptable callbacks | Yang Wang | 2026-06-24 | v7.3-rc1 |
| [`ae16ca815dfc`](https://github.com/torvalds/linux/commit/ae16ca815dfc917929ca10a2c83ee64fa7e0c433) | drm/amd: add AMDGPU_DEBUG_HIBERNATION_THAW_RESUME_GPU debug mask | Samuel Zhang | 2026-06-11 | v7.3-rc1 |
| [`1fc76380c6ce`](https://github.com/torvalds/linux/commit/1fc76380c6ce5440e3cd02ddec76067f83969dc0) | drm/amdgpu: Add IP block soft reset as a GPU recovery method | Timur Kristóf | 2026-06-17 | v7.3-rc1 |
| [`a8880289fd67`](https://github.com/torvalds/linux/commit/a8880289fd67e85d155dbe6d625e3f6fcd94ff51) | drm/amdgpu: drop debug_enable_ras_aca debug mask flag | Ce Sun | 2026-07-07 | v7.3-rc1 |
| [`6c9e0328d1de`](https://github.com/torvalds/linux/commit/6c9e0328d1dee58cd2ebbcc34b43eefc342d6d62) | drm/amd/pm: refactor PPT limits by controller and power source | Yang Wang | 2026-07-30 | v7.3-rc1 |
| [`534e172b888d`](https://github.com/torvalds/linux/commit/534e172b888d1f6aab271f054dae6dd8a2f18c74) | drm/amd/pm: refactor user PPT policy save and restore | Yang Wang | 2026-07-30 | v7.3-rc1 |
| [`cf9fa4d4d033`](https://github.com/torvalds/linux/commit/cf9fa4d4d0334b04cde3436f0ae0d3c5bb97cae8) | drm/amd/pm: restore user PPT limits after GPU reset | Yang Wang | 2026-07-31 | v7.3-rc1 |
| [`b6dc8f753670`](https://github.com/torvalds/linux/commit/b6dc8f753670e3833150482c1b7640b1fd3b30a3) | drm/amdgpu: add amdgpu.ptl module parameter for PTL control | Perry Yuan | 2026-02-09 | v7.2 |

Everything that matters for the patch surface landed in the v7.3 merge window (first tag
v7.3-rc1, 2026-08-30). The single v7.2 commit in the module-parameter area (`b6dc8f753670`)
did not touch our hunk regions.

## 1. The main power-limit rework

The rework is a three-commit series by Yang Wang (AMD), all first shipped in v7.3-rc1:

- [`6c9e0328d1de`](https://github.com/torvalds/linux/commit/6c9e0328d1dee58cd2ebbcc34b43eefc342d6d62)
  "drm/amd/pm: refactor PPT limits by controller and power source" — the core commit, 21
  files, +707/−695. This is the commit that removed the scalar
  `current_power_limit`/`default_power_limit`/`max_power_limit`/`min_power_limit` fields and
  introduced `struct smu_ppt_limit_context` with `range[SMU_POWER_SOURCE_COUNT][SMU_LIMIT_TYPE_COUNT]`
  and `supported_mask`, where `struct smu_ppt_limit_range` holds
  `{default_value, min, max, od_min, od_max}`.
- [`534e172b888d`](https://github.com/torvalds/linux/commit/534e172b888d1f6aab271f054dae6dd8a2f18c74)
  "drm/amd/pm: refactor user PPT policy save and restore" — reworks `user_dpm_profile`
  storage into per-power-source, per-controller values with validity masks
  (`ppt_limits[SMU_POWER_SOURCE_COUNT][SMU_LIMIT_TYPE_COUNT]`).
- [`cf9fa4d4d033`](https://github.com/torvalds/linux/commit/cf9fa4d4d0334b04cde3436f0ae0d3c5bb97cae8)
  "drm/amd/pm: restore user PPT limits after GPU reset" — small follow-up restoring the
  active PPT policy from SMU late init during reset recovery.

A same-author prep commit, [`719f83f3c675`](https://github.com/torvalds/linux/commit/719f83f3c67541b1392fb45851fb8ca7716dbde9)
"drm/amd/pm: drop unused smu pptable callbacks" (also first in v7.3-rc1), cleaned dead
callbacks on the same surface but does not touch the limit API itself.

The commit message of `6c9e0328d1de` states the intent: the old scalar model had several
structural limitations — "Controller identity, power source, capability, and PMFW state
share the same fields", "Combined callbacks cannot address PPT0 and PPT1 independently", and
"Cached current limits can become stale after PMFW reset". The new rules: index ranges by
AC/DC source and PPT0/PPT1 controller; store normal and overdrive capabilities separately;
pass the controller to get/set callbacks; assign each value a single owner (PPTable/platform
init for constant capabilities, PMFW for runtime state, common code for source and
overdrive range selection). It also notes that "Capable SMU 13.0.6 and SMU 15.0.8 platforms
expose PPT1 through the same interface" — see the ASIC section below for why that matters
for Navi 48.

`534e172b888d`'s message adds that a numeric policy value could not distinguish an explicit
zero from unset, one value per controller could not preserve independent AC and DC requests,
and suspend-only restore missed runtime resume, GPU reset, and table reload.

### Why the old smu.c hunk died (the ~2987 failure)

At v7.1, `drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c` has `smu_get_power_limit()` defined at
line 2911 with its `switch (limit_level)` cases at 2983–2996: `SMU_PPT_LIMIT_MIN` (line
2989) reads `smu->min_power_limit`, and `smu_set_power_limit()` sits at line 3000 clamping
against `min_power_limit`/`max_power_limit`. The 7.1-era patch hooked exactly those spots.
[`6c9e0328d1de`](https://github.com/torvalds/linux/commit/6c9e0328d1dee58cd2ebbcc34b43eefc342d6d62)
rewrote the entire region (150 changed lines in this one file), so the old hunks have no
context left to match. The rework is a pure rename-and-restructure from the patch's point of
view; the semantic hook points are the same functions under new names.

## 2. The rename and the AC/DC split

Same series, same commit: [`6c9e0328d1de`](https://github.com/torvalds/linux/commit/6c9e0328d1dee58cd2ebbcc34b43eefc342d6d62)
renamed `smu_get_power_limit()` → `smu_get_ppt_limit()` and `smu_set_power_limit()` →
`smu_set_ppt_limit()` (plus the ppt-funcs callbacks `get_power_limit`/`set_power_limit` →
`get_ppt_limit`/`set_ppt_limit` across smu11/13/14/15 backends), and replaced the scalar
limits with `smu->ppt_limits.range[power_source][limit_type]`, where `power_source` is
selected from `smu->adev->pm.ac_power` (SMU_POWER_SOURCE_AC/DC) and `limit_type` is
`SMU_PPT_LIMIT_PPT0`/`SMU_PPT_LIMIT_PPT1` (`SMU_DEFAULT_PPT_LIMIT`/`SMU_SLOW_PPT_LIMIT` alias
PPT0, `SMU_FAST_PPT_LIMIT` aliases PPT1). Reads are gated on
`smu->ppt_limits.supported_mask & BIT(limit_type)`. First containing tag: **v7.3-rc1**.
Nothing in v7.2 touched the limit API.

## 3. The amdgpu_drv.c module-parameter region (the ~149 failure)

The 7.1-era drv.c hunk anchored on this context at v7.1 (enum tail at line 149, variable
block immediately after):

```
	enum AMDGPU_DEBUG_MASK {
		...
		AMDGPU_DEBUG_ENABLE_CE_CS = BIT(10)
	};

+	bool amdgpu_ignore_min_pcap;          <-- insertion point
	unsigned int amdgpu_vram_limit = UINT_MAX;
```

Three commits rewrote that context between v7.1 and v7.3-rc1, in this order:

1. [`ae16ca815dfc`](https://github.com/torvalds/linux/commit/ae16ca815dfc917929ca10a2c83ee64fa7e0c433)
   (2026-06-11) — appended `, AMDGPU_DEBUG_HIBERNATION_THAW_RESUME_GPU = BIT(11),` and added
   the trailing comma to `AMDGPU_DEBUG_ENABLE_CE_CS = BIT(10),`. This is the **first
   context breaker**: the enum tail line the old hunk matches on changed text immediately.
2. [`1fc76380c6ce`](https://github.com/torvalds/linux/commit/1fc76380c6ce5440e3cd02ddec76067f83969dc0)
   (2026-06-17) — added `AMDGPU_DEBUG_DISABLE_IP_BLOCK_SOFT_RESET = BIT(12)`, which is now
   the enum tail that the 7.3-era patch's context shows.
3. [`a8880289fd67`](https://github.com/torvalds/linux/commit/a8880289fd67e85d155dbe6d625e3f6fcd94ff51)
   (2026-07-07) — removed `AMDGPU_DEBUG_ENABLE_RAS_ACA = BIT(4)`, shifting line numbers in
   the region up by one.

Net effect: two lines added, one removed around the enum, and the tail-line text changed —
git apply matches by context, so the old hunk fails on text, not just drift. All three are
first in **v7.3-rc1**. The insertion point itself (blank line between `};` and
`unsigned int amdgpu_vram_limit`) is unchanged, which is why the rebased 7.3 patch inserts
at the same place with updated context.

For completeness, [`b6dc8f753670`](https://github.com/torvalds/linux/commit/b6dc8f753670e3833150482c1b7640b1fd3b30a3)
(amdgpu.ptl, first in **v7.2**) also added a module parameter plus an `extern int amdgpu_ptl`
to amdgpu.h, but it inserted its variable at ~line 247 and its `module_param_named` at
~line 1115 of amdgpu_drv.c — nowhere near the enum tail at 149 or the
`extern int amdgpu_modeset;` block at ~line 156 of amdgpu.h, so it did not break our
amdgpu.h hunk (consistent with the observed two-hunk failure at rc3-60).

## 4. amdgpu_pm.c hwmon changes

None. `git log -S 'amdgpu_hwmon_show_power_cap_min'` and `-S 'PP_PWR_LIMIT_MIN'` over
v7.1..v7.3-rc5 return zero commits, and `git diff v7.1 v7.3-rc5 -- amdgpu_pm.c` contains no
`power_cap` hunks at all. `amdgpu_hwmon_show_power_cap_min()` (line 3421 at rc5, matching the
patch's `@@ -3422` context) was last touched in 2021 by
[`ae07970a0621`](https://github.com/torvalds/linux/commit/ae07970a0621d67a8bc0dc5b44e3fc652bd2ba20)
"drm/amd/pm: add support for hwmon control of slow and fast PPT limit on vangogh"
(Xiaomeng Hou, 2021-01-25). The read chain is unchanged in shape — hwmon →
`amdgpu_hwmon_show_power_cap_generic(dev, attr, buf, PP_PWR_LIMIT_MIN)` →
`amdgpu_dpm_get_power_limit()` → swsmu `pp_funcs->get_power_limit` — only the swsmu
implementation behind it was renamed to `smu_get_ppt_limit()`. The hwmon hunk therefore
applies unchanged on both 7.1 and 7.3 trees.

## 5. 7.2 versus 7.3, and rc5 → tip verification

- **7.2 shipped nothing relevant.** The only amdgpu_smu.c commits in the v7.2 window are
  [`7e9a8506a857`](https://github.com/torvalds/linux/commit/7e9a8506a857bbdd99759b0ede03a0c805893920)
  (SMU 15.0.5 support), [`e2469bde3fca`](https://github.com/torvalds/linux/commit/e2469bde3fcaa087dcfeccbc6306a9e76a79344e)
  (SMU 15.0.9 support), and [`75c8746b9d0a`](https://github.com/torvalds/linux/commit/75c8746b9d0a0317d8a58aa0efa2ff2f7359908b)
  (APU display↔XHCI device link) — none touch the limit API. In drv.c/amdgpu.h only
  `b6dc8f753670` (ptl param) landed, outside our hunk regions. The 7.1-era patch applies
  fine to v7.2.
- **Everything relevant is 7.3.** The rework series and all three enum commits are first in
  v7.3-rc1. So: 7.1-era patch = v7.1 through v7.2.x and early 7.3-rc trees up to the enum
  break; once the rework lands (v7.3-rc1), the smu.c hunks cannot apply at all.
- **rc5 → tip is clean.** `git diff --stat v7.3-rc5 551c722f40809618230001baccf219193e22fc5a`
  over the four patched files is empty (byte-identical, confirming the bundle header), and
  `git log v7.3-rc5..tip -- drivers/gpu/drm/amd/pm/` is empty — zero commits in the entire
  power-management subtree, which covers amdgpu_smu.c, amdgpu_pm.c, amdgpu_dpm.c, swsmu
  headers, and every ppt backend. The tip itself is the rtc-7.3-fixes merge, unrelated.
  Nothing needs a second rebase for the 7.3 development window so far.

## Adjacent: which SMU backend handles Navi 48

`smu_set_funcs()` in `drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c` dispatches on the MP1
(`MP1_HWIP`) IP version reported by ip discovery at rc5:

| MP1 `IP_VERSION` | Backend (`set_ppt_funcs`) | File |
|---|---|---|
| (14,0,2), (14,0,3) | `smu_v14_0_2_set_ppt_funcs` | `smu14/smu_v14_0_2_ppt.c` |
| (14,0,0), (14,0,1), (14,0,4), (14,0,5) | `smu_v14_0_0_set_ppt_funcs` | `smu14/smu_v14_0_0_ppt.c` |
| (13,0,6), (13,0,14), (13,0,12) | `smu_v13_0_6_set_ppt_funcs` (od_enabled = true) | `smu13/smu_v13_0_6_ppt.c` |
| (15,0,8) | `smu_v15_0_8_set_ppt_funcs` (od_enabled = true) | `smu15/smu_v15_0_8_ppt.c` |

Navi 48 (device 1002:7550, Radeon RX 9070 series) reports MP1 IP 14.0.2 and therefore routes
to **smu14/smu_v14_0_2_ppt.c**. In-tree device-table evidence is absent by design: `git grep
0x7550` at rc5 hits only unrelated SMU 13.0.6 firmware-version constants, because modern
amdgpu binds dGPUs by ip discovery rather than static PCI ID tables (the drv.c table only
carries quirk-flagged entries). The routing evidence is the MP1 switch above plus the
(14,0,3) firmware special case inside `smu_v14_0_2_ppt.c` itself (energy accumulator only
when `mp1_ver == IP_VERSION(14, 0, 3)`), showing 14.0.2 and 14.0.3 are the two dGPU variants
of this backend.

Severity-relevant detail: at rc5 `smu_v14_0_2_ppt.c` sets only
`supported_mask |= BIT(SMU_PPT_LIMIT_PPT0)`; PPT1 is added conditionally only by
`smu_v13_0_6_ppt.c` and `smu_v15_0_8_ppt.c`, exactly matching the rework commit's note that
PPT1 exists on "SMU 13.0.6 and SMU 15.0.8 platforms". So on Navi 48 the patch's
`supported_mask & BIT(limit_type)` context always evaluates the PPT0 path, the
`[power_source][PPT0]` range is the only live entry, and the `ignore_min_pcap` override
flows through `smu_get_ppt_limit`/`smu_set_ppt_limit` for the PPT0 controller on both AC and
DC.

## References

- Bundle under discussion: [`files/linux-config-debplus/hotfixes/amdgpu-power.sh`](/files/linux-config-debplus/hotfixes/amdgpu-power.sh)
  (verified against v7.3-rc5 `72d3fcf802c4` and tip `551c722f4080`).
- Rework series: [`6c9e0328d1de`](https://github.com/torvalds/linux/commit/6c9e0328d1dee58cd2ebbcc34b43eefc342d6d62),
  [`534e172b888d`](https://github.com/torvalds/linux/commit/534e172b888d1f6aab271f054dae6dd8a2f18c74),
  [`cf9fa4d4d033`](https://github.com/torvalds/linux/commit/cf9fa4d4d0334b04cde3436f0ae0d3c5bb97cae8) — all in v7.3-rc1.
- drv.c enum churn: [`ae16ca815dfc`](https://github.com/torvalds/linux/commit/ae16ca815dfc917929ca10a2c83ee64fa7e0c433),
  [`1fc76380c6ce`](https://github.com/torvalds/linux/commit/1fc76380c6ce5440e3cd02ddec76067f83969dc0),
  [`a8880289fd67`](https://github.com/torvalds/linux/commit/a8880289fd67e85d155dbe6d625e3f6fcd94ff51) — all in v7.3-rc1.
- hwmon baseline: [`ae07970a0621`](https://github.com/torvalds/linux/commit/ae07970a0621d67a8bc0dc5b44e3fc652bd2ba20) (2021, vangogh hwmon PPT).
