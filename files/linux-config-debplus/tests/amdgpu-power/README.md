# AMDGPU power hotfix regression tests

From the Compfuzor repository root:

```sh
files/linux-config-debplus/tests/amdgpu-power/run.py --kernel-repo /usr/local/src/linux
```

For a copied bundle, invoke its absolute path from any directory and choose a
writable scratch directory explicitly, for example:

```sh
/usr/local/src/linux-config-debplus/tests/amdgpu-power/run.py \
  --kernel-repo /usr/local/src/linux \
  --scratch-dir "$HOME/tmp-opencode/linux-debplus-7.3/hotfix"
```

Requires Python 3.12+, Git, and a C compiler (`CC` may select one). Reads Git
objects only; the kernel checkout and its configuration are never changed.
Archives five source files into temporary directories under
`--scratch-dir` (default: `.test-agent/linux-debplus-7.3/hotfix/` beneath the
current working directory) and removes those test directories on exit. Hotfix
invocations set `TMPDIR` to their temporary test directory, keeping the embedded
patch temporary files within the same scratch root. No repository layout is
assumed for the scratch location.

Checks both pinned upstream 7.3 development tip
`551c722f40809618230001baccf219193e22fc5a` and rc5 baseline
`72d3fcf802c45d00b300f25b848a93c3a2bd7c7e`, including four-file byte identity.
Tests application, read-only checks, repeat application, reverse applicability,
and all-or-none failure on partial and incompatible source trees, including
plain source directories nested inside this unrelated Git repository.

The C harness compiles the **actual patched** `smu_get_ppt_limit`,
`smu_set_ppt_limit`, and `amdgpu_hwmon_show_power_cap_min` extracted from archived
source. Stubs replace kernel types and firmware callbacks, not policy logic.
Assertions cover AC/DC, OD on/off, sustained/fast, override on/off, upper/lower
bounds, masks/enums, device-disabled failures, current/default/max readback,
zero/default sentinel, firmware failure, profile recording/restoration, and hwmon.
This is not a kernel build or hardware/firmware acceptance test.

## Port scope and hardware limitation

Compared with the imported 7.1 patch, 7.3 uses shared PPT APIs and per-source,
per-type `min`/`od_min` and `max`/`od_max` ranges. The override now selects zero
for the effective minimum in the shared setter and minimum getter, for every
supported sustained/fast cap. All other policy and callback paths stay upstream.

The firmware-specific SMU 13.0.6 and 15.0.8 fast-PPT setters still reject caps
below `PPT1Min` before issuing firmware messages. Thus minimum readback can be
zero while a lower fast cap returns `-EINVAL` on those devices. This is a real
reporting/acceptance mismatch, not silent success; the patch deliberately does
not alter firmware-specific checks. Generic callback failure tests verify error
propagation and no user-profile update. References at the pinned tip:

- [Linux `smu_v13_0_6_ppt.c`, lines 1762–1788](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/gpu/drm/amd/pm/swsmu/smu13/smu_v13_0_6_ppt.c#L1762-L1788).
- [Linux `smu_v15_0_8_ppt.c`, fast-PPT minimum check](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/gpu/drm/amd/pm/swsmu/smu15/smu_v15_0_8_ppt.c#L2244-L2270).
- [Shared PPT API](https://github.com/torvalds/linux/blob/551c722f40809618230001baccf219193e22fc5a/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c#L2936-L3065).
