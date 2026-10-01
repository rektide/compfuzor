/* Minimal kernel types and observable firmware stubs; production functions
 * are extracted verbatim by run.py and appended after this header. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>

#define BIT(n) (1U << (n))
#define dev_err(...) ((void)0)
#define SMU_DPM_USER_PROFILE_RESTORE BIT(0)
enum smu_power_src_type { SMU_POWER_SOURCE_AC, SMU_POWER_SOURCE_DC };
enum smu_ppt_limit_type { SMU_PPT_LIMIT_PPT0, SMU_PPT_LIMIT_PPT1, SMU_LIMIT_TYPE_COUNT };
#define SMU_DEFAULT_PPT_LIMIT SMU_PPT_LIMIT_PPT0
#define SMU_SLOW_PPT_LIMIT SMU_PPT_LIMIT_PPT0
#define SMU_FAST_PPT_LIMIT SMU_PPT_LIMIT_PPT1
enum pp_power_limit_level { PP_PWR_LIMIT_MIN = -1, PP_PWR_LIMIT_CURRENT,
                          PP_PWR_LIMIT_DEFAULT, PP_PWR_LIMIT_MAX };
enum smu_ppt_limit_level { SMU_PPT_LIMIT_MIN = -1, SMU_PPT_LIMIT_CURRENT,
                         SMU_PPT_LIMIT_DEFAULT, SMU_PPT_LIMIT_MAX };
enum pp_power_type { PP_PWR_TYPE_SUSTAINED, PP_PWR_TYPE_FAST };
struct smu_ppt_limit_range { uint32_t min, max, od_min, od_max, default_value; };
struct amdgpu_device { struct { bool dpm_enabled, ac_power; } pm; void *dev; };
struct smu_context;
struct ppt_funcs {
    int (*set_ppt_limit)(struct smu_context *, enum smu_ppt_limit_type, uint32_t);
};
struct smu_context {
    bool pm_enabled, od_enabled;
    struct amdgpu_device *adev;
    struct { uint32_t supported_mask; struct smu_ppt_limit_range range[2][2]; } ppt_limits;
    struct ppt_funcs *ppt_funcs;
    struct {
        uint32_t flags, ppt_limits[2][2], ppt_limit_user_mask[2];
    } user_dpm_profile;
};
static bool amdgpu_ignore_min_pcap;
static int get_error, set_error, get_calls, set_calls;
static uint32_t current_limit = 60, sent_limit, sent_type;
static int smu_get_asic_ppt_limit(struct smu_context *smu, uint32_t type, uint32_t *limit)
{
    (void)smu; (void)type;
    get_calls++;
    if (get_error)
        return get_error;
    *limit = current_limit;
    return 0;
}
static int set_firmware(struct smu_context *smu, enum smu_ppt_limit_type type, uint32_t limit)
{
    (void)smu;
    set_calls++;
    sent_type = type;
    sent_limit = limit;
    return set_error;
}
struct device { int unused; };
struct device_attribute { int unused; };
static int hwmon_calls;
static ssize_t sysfs_emit(char *buf, const char *format)
{
    return sprintf(buf, "%s", format);
}
static ssize_t amdgpu_hwmon_show_power_cap_generic(struct device *dev,
        struct device_attribute *attr, char *buf, enum pp_power_limit_level level)
{
    (void)dev; (void)attr;
    assert(level == PP_PWR_LIMIT_MIN);
    hwmon_calls++;
    return sprintf(buf, "40000000\n");
}
