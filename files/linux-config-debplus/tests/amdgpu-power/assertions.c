/* Assertions invoke the real patched source functions, never model logic. */
int main(void)
{
    struct amdgpu_device adev = { .pm = { .dpm_enabled = true, .ac_power = true } };
    struct ppt_funcs funcs = { .set_ppt_limit = set_firmware };
    struct smu_context smu = { .pm_enabled = true, .adev = &adev, .ppt_funcs = &funcs };
    uint32_t out;
    int ac, od, type, enabled;
    char buf[32];

    for (ac = 0; ac < 2; ac++)
        for (type = 0; type < 2; type++) {
            struct smu_ppt_limit_range *r = &smu.ppt_limits.range[ac][type];
            r->min = 40 + ac * 10 + type;
            r->max = 100 + ac * 10 + type;
            r->od_min = 20 + ac * 10 + type;
            r->od_max = 150 + ac * 10 + type;
            r->default_value = 70 + ac * 10 + type;
        }
    smu.ppt_limits.supported_mask = BIT(0) | BIT(1);
    for (ac = 0; ac < 2; ac++)
        for (od = 0; od < 2; od++)
            for (type = 0; type < 2; type++)
                for (enabled = 0; enabled < 2; enabled++) {
                    enum pp_power_type pp_type = type ? PP_PWR_TYPE_FAST : PP_PWR_TYPE_SUSTAINED;
                    struct smu_ppt_limit_range *r = &smu.ppt_limits.range[ac][type];
                    uint32_t min = od ? r->od_min : r->min;
                    uint32_t max = od ? r->od_max : r->max;
                    adev.pm.ac_power = ac == SMU_POWER_SOURCE_AC;
                    smu.od_enabled = od;
                    amdgpu_ignore_min_pcap = enabled;
                    memset(&smu.user_dpm_profile, 0, sizeof(smu.user_dpm_profile));
                    get_calls = set_calls = 0;
                    assert(!smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_MIN, pp_type));
                    assert(out == (enabled ? 0 : min));
                    assert(!smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_MAX, pp_type));
                    assert(out == max);
                    assert(!smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_DEFAULT, pp_type));
                    assert(out == r->default_value);
                    assert(!smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_CURRENT, pp_type));
                    assert(out == current_limit && get_calls == 1);
                    assert(smu_set_ppt_limit(&smu, type, min - 1) == (enabled ? 0 : -EINVAL));
                    assert(set_calls == enabled);
                    if (enabled) {
                        assert(sent_limit == min - 1 && sent_type == (uint32_t)type);
                        assert(smu.user_dpm_profile.ppt_limits[ac][type] == min - 1);
                        assert(smu.user_dpm_profile.ppt_limit_user_mask[ac] == BIT(type));
                        assert(!smu.user_dpm_profile.ppt_limit_user_mask[!ac]);
                    }
                    assert(smu_set_ppt_limit(&smu, type, max + 1) == -EINVAL);
                    assert(set_calls == enabled);
                    assert(!smu_set_ppt_limit(&smu, type, min));
                    assert(!smu_set_ppt_limit(&smu, type, max));
                    /* Firmware rejection must not become silent success/update. */
                    memset(&smu.user_dpm_profile, 0, sizeof(smu.user_dpm_profile));
                    set_error = -EIO;
                    assert(smu_set_ppt_limit(&smu, type, min) == -EIO);
                    if (enabled)
                        assert(smu_set_ppt_limit(&smu, type, min - 1) == -EIO);
                    assert(!smu.user_dpm_profile.ppt_limit_user_mask[ac]);
                    assert(!smu.user_dpm_profile.ppt_limits[ac][type]);
                    set_error = 0;
                    smu.user_dpm_profile.flags = SMU_DPM_USER_PROFILE_RESTORE;
                    assert(!smu_set_ppt_limit(&smu, type, min));
                    assert(!smu.user_dpm_profile.ppt_limit_user_mask[ac]);
                    smu.user_dpm_profile.flags = 0;
                    /* Unsupported caps stay unsupported with the override on. */
                    smu.ppt_limits.supported_mask &= ~BIT(type);
                    out = 999;
                    assert(smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_MIN, pp_type) == -EOPNOTSUPP);
                    assert(out == 999);
                    assert(smu_set_ppt_limit(&smu, type, min) == -EOPNOTSUPP);
                    smu.ppt_limits.supported_mask |= BIT(type);
                }
    amdgpu_ignore_min_pcap = true;
    assert(smu_get_ppt_limit(&smu, NULL, PP_PWR_LIMIT_MIN, PP_PWR_TYPE_FAST) == -EINVAL);
    assert(smu_get_ppt_limit(&smu, &out, 99, PP_PWR_TYPE_FAST) == -EOPNOTSUPP);
    assert(smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_MIN, 99) == -EOPNOTSUPP);
    assert(smu_set_ppt_limit(&smu, SMU_LIMIT_TYPE_COUNT, 1) == -EINVAL);
    assert(smu_set_ppt_limit(&smu, UINT32_MAX, 1) == -EINVAL);
    for (enabled = 0; enabled < 2; enabled++) {
        amdgpu_ignore_min_pcap = enabled;
        get_calls = 0;
        current_limit = 60;
        assert(!smu_set_ppt_limit(&smu, SMU_DEFAULT_PPT_LIMIT, 0));
        assert(get_calls == 1 && sent_limit == current_limit);
        get_error = -EIO;
        set_calls = 0;
        memset(&smu.user_dpm_profile, 0, sizeof(smu.user_dpm_profile));
        assert(smu_set_ppt_limit(&smu, SMU_DEFAULT_PPT_LIMIT, 0) == -EIO);
        assert(!set_calls && !smu.user_dpm_profile.ppt_limit_user_mask[1]);
        assert(smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_CURRENT, PP_PWR_TYPE_FAST) == -EIO);
        get_error = 0;
        /* Fast zero is not the default-cap sentinel. */
        get_calls = 0;
        assert(smu_set_ppt_limit(&smu, SMU_FAST_PPT_LIMIT, 0) == (enabled ? 0 : -EINVAL));
        assert(!get_calls);
        if (enabled)
            assert(!sent_limit);
        current_limit = 999;
        assert(smu_set_ppt_limit(&smu, SMU_DEFAULT_PPT_LIMIT, 0) == -EINVAL);
        current_limit = 60;
    }
    funcs.set_ppt_limit = NULL;
    assert(smu_set_ppt_limit(&smu, SMU_FAST_PPT_LIMIT, 60) == -EOPNOTSUPP);
    funcs.set_ppt_limit = set_firmware;
    for (enabled = 0; enabled < 2; enabled++) {
        smu.pm_enabled = !enabled;
        adev.pm.dpm_enabled = enabled;
        assert(smu_get_ppt_limit(&smu, &out, PP_PWR_LIMIT_MIN, PP_PWR_TYPE_FAST) == -EOPNOTSUPP);
        assert(smu_set_ppt_limit(&smu, SMU_FAST_PPT_LIMIT, 1) == -EOPNOTSUPP);
    }
    amdgpu_ignore_min_pcap = false;
    assert(amdgpu_hwmon_show_power_cap_min(NULL, NULL, buf) == 9);
    assert(!strcmp(buf, "40000000\n") && hwmon_calls == 1);
    amdgpu_ignore_min_pcap = true;
    assert(amdgpu_hwmon_show_power_cap_min(NULL, NULL, buf) == 2);
    assert(!strcmp(buf, "0\n") && hwmon_calls == 1);
    puts("compiled patched SMU getter/setter and hwmon assertions passed");
    return 0;
}
