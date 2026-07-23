# install-kernel-bls.sh -- regenerate systemd-boot BLS entries from /etc/kernel/cmdline.
#
# install-kernel-cmdline.sh and install-kernel-params.sh write module params and
# raw tokens to /etc/kernel/cmdline, but that file only takes effect once
# `kernel-install` regenerates the BLS entries on the EFI System Partition.
# This step bridges that gap so a plain install.sh actually lands the cmdline.
#
# Gated by KERNEL_INSTALL (default off): kernel-install writes to the ESP and is
# usually wanted at the end of an explicit install, not on every partial apply.
# When skipped it warns loudly so the cmdline->BLS gap is never silent.
# Set KERNEL_INSTALL=1 to run it.
#
# Contributed by the kernel_bls subsys (active when the config writes cmdline
# via KERNEL_MODULES or KERNEL_PARAMS), ordered last so it runs after the other
# install-kernel*.sh steps, then runs status.sh for post-install drift.

if [ "${KERNEL_INSTALL:-0}" = "1" ]; then
  _bls_kv="$(uname -r)"
  # Locate the kernel image. systemd's default (/usr/lib/modules/$kv/vmlinuz)
  # rarely exists on Debian/custom kernels -- the image usually lives at
  # /boot/vmlinuz-$kv. KERNEL_IMAGE overrides everything for odd layouts.
  _bls_kimg=""
  for _bls_cand in "${KERNEL_IMAGE:-}" "/boot/vmlinuz-$_bls_kv" "/usr/lib/modules/$_bls_kv/vmlinuz" "/lib/modules/$_bls_kv/vmlinuz"; do
    [ -n "$_bls_cand" ] && [ -f "$_bls_cand" ] && { _bls_kimg="$_bls_cand"; break; }
  done
  if [ -z "$_bls_kimg" ]; then
    echo "${NAME}: KERNEL_INSTALL=1 but no kernel image for $_bls_kv." >&2
    echo "  looked in /boot/vmlinuz-$_bls_kv, /usr/lib/modules/$_bls_kv/vmlinuz, /lib/modules/$_bls_kv/vmlinuz." >&2
    echo "  set KERNEL_IMAGE=/path/to/vmlinuz to override." >&2
  else
    kernel-install add "$_bls_kv" "$_bls_kimg"
  fi
else
  echo "${NAME}: KERNEL_INSTALL not set -- skipping BLS regen." >&2
  echo "  /etc/kernel/cmdline was updated but BLS entries were NOT;" >&2
  echo "  changes won't take effect until the next kernel-install or reboot." >&2
  echo "  re-run with: sudo KERNEL_INSTALL=1 \"$DIR/bin/install.sh\"" >&2
fi

# status: report drift now that install has applied.
if [ -x "$DIR/bin/status.sh" ]; then
  "$DIR/bin/status.sh" "$@" || true
fi
