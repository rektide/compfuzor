#!/bin/sh
# Apply the amdgpu.ignore_min_pcap hotfix to a Linux kernel source tree.
# Verified against v7.3-rc5 (72d3fcf802c45d00b300f25b848a93c3a2bd7c7e).
# Also verified against 7.3 development tip 551c722f40809618230001baccf219193e22fc5a.

set -eu

usage()
{
	cat <<EOF
Usage: $0 [--check] [KERNEL_TREE]

Apply the AMDGPU minimum power-cap override. If KERNEL_TREE is omitted, the
current directory is used when it is a kernel tree; otherwise, the script
looks for the linux checkout beside linux-config-debplus.

Options:
  --check  Verify that the hotfix applies without changing any files.
  -h       Show this help.
EOF
}

check_only=0
case "${1:-}" in
	--check)
		check_only=1
		shift
		;;
	-h|--help)
		usage
		exit 0
		;;
esac

if [ "$#" -gt 1 ]; then
	usage >&2
	exit 2
fi

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

if [ "$#" -eq 1 ]; then
	kernel_tree=$1
elif [ -f Makefile ] && [ -d drivers/gpu/drm/amd ]; then
	kernel_tree=.
elif [ -f "$script_dir/../../linux/Makefile" ] &&
     [ -d "$script_dir/../../linux/drivers/gpu/drm/amd" ]; then
	kernel_tree=$script_dir/../../linux
else
	echo "AMD-HOTFIX: cannot locate a Linux kernel source tree." >&2
	echo "Usage: $0 [--check] [KERNEL_TREE]" >&2
	exit 1
fi

if [ ! -f "$kernel_tree/Makefile" ] ||
   [ ! -f "$kernel_tree/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c" ]; then
	echo "AMD-HOTFIX: '$kernel_tree' is not a Linux kernel source tree." >&2
	exit 1
fi

patch_file=$(mktemp "${TMPDIR:-/tmp}/amdgpu-ignore-min-pcap.XXXXXX.patch")
trap 'rm -f "$patch_file"' EXIT HUP INT TERM

cat >"$patch_file" <<'PATCH'
diff --git a/drivers/gpu/drm/amd/amdgpu/amdgpu.h b/drivers/gpu/drm/amd/amdgpu/amdgpu.h
--- a/drivers/gpu/drm/amd/amdgpu/amdgpu.h
+++ b/drivers/gpu/drm/amd/amdgpu/amdgpu.h
@@ -156,6 +156,7 @@ struct amdgpu_watchdog_timer {
  * Modules parameters.
  */
 extern int amdgpu_modeset;
+extern bool amdgpu_ignore_min_pcap;
 extern unsigned int amdgpu_vram_limit;
 extern int amdgpu_vis_vram_limit;
 extern int amdgpu_gart_size;
diff --git a/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c b/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
--- a/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
+++ b/drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
@@ -149,6 +149,7 @@ enum AMDGPU_DEBUG_MASK {
 	AMDGPU_DEBUG_DISABLE_IP_BLOCK_SOFT_RESET = BIT(12),
 };
 
+bool amdgpu_ignore_min_pcap;
 unsigned int amdgpu_vram_limit = UINT_MAX;
 int amdgpu_vis_vram_limit;
 int amdgpu_gart_size = -1; /* auto */
@@ -271,6 +272,15 @@ struct amdgpu_watchdog_timer amdgpu_watchdog_timer = {
 	.period = 0x0, /* default to 0x0 (timeout disable) */
 };
 
+/**
+ * DOC: ignore_min_pcap (bool)
+ * Ignore the minimum power cap reported by the GPU firmware. This is useful
+ * on graphics cards whose firmware reports an excessively high minimum.
+ * The default is false.
+ */
+MODULE_PARM_DESC(ignore_min_pcap, "Ignore the minimum power cap");
+module_param_named(ignore_min_pcap, amdgpu_ignore_min_pcap, bool, 0600);
+
 /**
  * DOC: vramlimit (int)
  * Restrict the total amount of VRAM in MiB for testing.  The default is 0 (Use full VRAM).
diff --git a/drivers/gpu/drm/amd/pm/amdgpu_pm.c b/drivers/gpu/drm/amd/pm/amdgpu_pm.c
--- a/drivers/gpu/drm/amd/pm/amdgpu_pm.c
+++ b/drivers/gpu/drm/amd/pm/amdgpu_pm.c
@@ -3422,6 +3422,9 @@ static ssize_t amdgpu_hwmon_show_power_cap_min(struct device *dev,
 					 struct device_attribute *attr,
 					 char *buf)
 {
+	if (amdgpu_ignore_min_pcap)
+		return sysfs_emit(buf, "0\n");
+
 	return amdgpu_hwmon_show_power_cap_generic(dev, attr, buf, PP_PWR_LIMIT_MIN);
 }
 
diff --git a/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c b/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c
--- a/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c
+++ b/drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c
@@ -3001,9 +3001,12 @@ int smu_get_ppt_limit(void *handle,
 			smu->ppt_limits.range[power_source][limit_type].max;
 		break;
 	case SMU_PPT_LIMIT_MIN:
-		*limit = smu->od_enabled ?
-			smu->ppt_limits.range[power_source][limit_type].od_min :
-			smu->ppt_limits.range[power_source][limit_type].min;
+		if (amdgpu_ignore_min_pcap)
+			*limit = 0;
+		else
+			*limit = smu->od_enabled ?
+				smu->ppt_limits.range[power_source][limit_type].od_min :
+				smu->ppt_limits.range[power_source][limit_type].min;
 		break;
 	default:
 		return -EINVAL;
@@ -3028,7 +3031,8 @@ static int smu_set_ppt_limit(void *handle, uint32_t limit_type, uint32_t limit)
 	power_source = smu->adev->pm.ac_power ?
 		SMU_POWER_SOURCE_AC : SMU_POWER_SOURCE_DC;
 	range = &smu->ppt_limits.range[power_source][limit_type];
-	min_limit = smu->od_enabled ? range->od_min : range->min;
+	min_limit = amdgpu_ignore_min_pcap ? 0 :
+		(smu->od_enabled ? range->od_min : range->min);
 	max_limit = smu->od_enabled ? range->od_max : range->max;
 
 	if (!(smu->ppt_limits.supported_mask & BIT(limit_type)))
PATCH

kernel_tree=$(CDPATH='' cd -- "$kernel_tree" && pwd)
echo "AMD-HOTFIX: kernel tree: $kernel_tree"

# A plain source directory may sit inside another repository. Do not let git
# discover that parent and silently skip this tree's patch paths.
export GIT_CEILING_DIRECTORIES="$(dirname -- "$kernel_tree")"

if git -C "$kernel_tree" apply --reverse --check "$patch_file" 2>/dev/null; then
	echo "AMD-HOTFIX: hotfix is already applied."
	exit 0
fi

if ! git -C "$kernel_tree" apply --check "$patch_file"; then
	echo "AMD-HOTFIX: hotfix does not apply to this source tree." >&2
	echo "No source files were changed." >&2
	exit 1
fi

if [ "$check_only" -eq 1 ]; then
	echo "AMD-HOTFIX: hotfix applies cleanly; no files changed."
	exit 0
fi

git -C "$kernel_tree" apply "$patch_file"

echo "AMD-HOTFIX: hotfix applied successfully."
echo "Enable it with the kernel parameter: amdgpu.ignore_min_pcap=1"
