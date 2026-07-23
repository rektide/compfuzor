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
  kernel-install add "$(uname -r)" "/lib/modules/$(uname -r)/vmlinuz"
else
  echo "${NAME}: KERNEL_INSTALL not set -- skipping BLS regen." >&2
  echo "  /etc/kernel/cmdline was updated but BLS entries were NOT;" >&2
  echo "  changes won't take effect until the next kernel-install or reboot." >&2
  echo "  set KERNEL_INSTALL=1, or run:" >&2
  echo "    sudo kernel-install add \"$(uname -r)\" \"/lib/modules/$(uname -r)/vmlinuz\"" >&2
fi

# status: report drift now that install has applied.
if [ -x "$DIR/bin/status.sh" ]; then
  "$DIR/bin/status.sh" "$@" || true
fi
