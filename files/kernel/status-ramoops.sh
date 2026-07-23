# status-ramoops.sh -- the one ramoops health check nothing else covers.
#
# The rest is already reusable elsewhere: status-modules.ts covers the
# pstore/ramoops *param* drift (pstore.backend, ramoops.mem_address, ...),
# status-cmdline.ts covers the raw memmap= token, and status-dirs.sh surfaces
# /sys/fs/pstore. What only a ramoops-aware check can assert is the kernel log:
# a CLEAN registration -- "Registered ramoops" and NOT "already in use" (the
# latter means efi_pstore grabbed the backend slot and ramoops silently failed,
# which the param checks won't catch since ramoops still loads).
#
# Contributed by the kernel_bls subsys (active for ramoops cmdline configs).
# status.sh reporter conventions: exit 0 clean, 1 drift, 2 not-applicable.

_drift=0
_say() { printf '%-12s %s\n' "$1" "$2"; }

if command -v journalctl >/dev/null 2>&1; then
  _klog="$(journalctl -k --no-pager 2>/dev/null || true)"
  if [ -n "$_klog" ]; then
    if printf '%s\n' "$_klog" | grep -q 'Registered ramoops'; then
      if printf '%s\n' "$_klog" | grep -q 'already in use'; then
        _say journal "DRIFT: 'Registered ramoops' BUT also 'already in use' -- efi_pstore stole the slot"; _drift=1
      else
        _say journal "OK: Registered ramoops, no 'already in use'"
      fi
    else
      _say journal "DRIFT: no 'Registered ramoops' this boot"; _drift=1
    fi
  else
    _say journal "n/a: kernel journal not readable (run under root?)"
  fi
else
  _say journal "n/a: journalctl unavailable"
fi

exit $_drift
