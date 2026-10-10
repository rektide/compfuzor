# Debos/fakemachine scratch files can be large; keep them on the deployment's
# disk rather than the host's /tmp tmpfs. Allow an explicit caller override.
export TMPDIR="${TMPDIR:-$DIR/tmp}"
mkdir -p "$TMPDIR"

# Keep the deployment checkout pristine and retain upstream build artifacts.
mkdir -p "$DIR/build"
rsync -a --exclude=/.git --exclude=/.jj "$REPO_DIR/" "$DIR/build/"
cd "$DIR/build"

# Upstream has no kernel-package option. Specialize the copied SDM845 recipe
# and select its boot kernel explicitly rather than relying on linux-version's
# ordering when several kernels are installed.
python3 - {{ MOBIAN_KERNEL | quote }} <<'PY'
from pathlib import Path
import re
import sys

kernel = sys.argv[1]
if not re.fullmatch(r"linux-image-[a-z0-9.+-]+-sdm845", kernel):
    raise SystemExit(f"Expected an SDM845 kernel package, got {kernel!r}")

packages = Path("devices/qcom/packages-base.yaml")
text, count = re.subn(
    r"^      - .*\$device.*-support$",
    f"      - qcom-support-common\n      - {kernel}",
    packages.read_text(),
    flags=re.MULTILINE,
)
if count != 1:
    raise SystemExit("Upstream Qualcomm package recipe changed; review kernel selection")
packages.write_text(text)

bootloader = Path("devices/qcom/bootloader.sh")
text = bootloader.read_text()
needle = "KERNEL_VERSION=$(linux-version list | tail -1)"
if text.count(needle) != 1:
    raise SystemExit("Upstream Qualcomm bootloader changed; review kernel selection")
replacement = f"""KERNEL_VERSION=$(dpkg-query -L {kernel} | sed -n 's|^/boot/vmlinuz-||p')
if [ -z "$KERNEL_VERSION" ] || [ ! -f "/boot/vmlinuz-$KERNEL_VERSION" ] || [ ! -f "/boot/initrd.img-$KERNEL_VERSION" ]; then
    echo "Missing kernel or initramfs from {kernel}" >&2
    exit 1
fi"""
bootloader.write_text(text.replace(needle, replacement))
PY

exec ./build.sh -t sdm845 \
  -e {{ MOBIAN_ENVIRONMENT | quote }} \
  -x {{ MOBIAN_DEBIAN_SUITE | quote }} \
  -S {{ MOBIAN_SUITE | quote }} "$@"
