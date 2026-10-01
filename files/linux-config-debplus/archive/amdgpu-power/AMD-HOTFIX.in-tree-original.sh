#!/bin/sh
# Archived original AMD-HOTFIX.sh script for the amdgpu ignore_min_pcap patch
#
# This script applies the patch from freedesktop.org that adds the
# amdgpu.ignore_min_pcap kernel parameter to allow setting power limits
# below the BIOS-defined minimum.
#
# USAGE:
#   ./AMD-HOTFIX.sh
#
# WHAT THIS PATCH DOES:
#   Some AMD GPUs enforce an artificially high minimum power limit that prevents
#   users from reducing power consumption. For example, an RX 7900 XTX with a
#   355W TDP may have a minimum power cap of 272W, preventing you from
#   running at 200W or lower.
#
#   This patch adds a kernel parameter 'amdgpu.ignore_min_pcap' that, when set
#   to 1, removes this minimum limit enforcement, allowing power limits as low
#   as 0 (though realistically you'll want something like 150-200W).
#
# AFTER APPLYING THE PATCH:
#   1. Build your kernel:
#      make -j$(nproc)
#      make modules_install
#      make install
#
#   2. Add the kernel parameter to your boot configuration:
#      Add 'amdgpu.ignore_min_pcap=1' to your kernel command line.
#      - For GRUB: Edit /etc/default/grub and add to GRUB_CMDLINE_LINUX_DEFAULT
#      - Then run: grub-mkconfig -o /boot/grub/grub.cfg
#
#   3. Set your desired power limit:
#      echo 150 | sudo tee /sys/class/hwmon/hwmonX/power1_cap
#      (replace X with the appropriate hwmon number for your GPU)
#
#   4. Verify the limit:
#      cat /sys/class/hwmon/hwmonX/power1_cap
#
# TO UNDO THE PATCH:
#   git restore drivers/gpu/drm/amd/amdgpu/amdgpu.h
#   git restore drivers/gpu/drm/amd/amdgpu/amdgpu_drv.c
#   git restore drivers/gpu/drm/amd/pm/amdgpu_pm.c
#   git restore drivers/gpu/drm/amd/pm/swsmu/amdgpu_smu.c
#
# REFERENCES:
#   - Zen Kernel Issue #344: https://github.com/zen-kernel/zen-kernel/issues/344
#   - Patch Source: https://gitlab.freedesktop.org/drm/amd/uploads/4af61751f8fa08340990b48824e4f9c5/amdgpu-ignore-min-pcap.patch
#

set -e

PATCH_FILE="amdgpu-ignore-min-pcap.patch"
PATCH_URL="https://gitlab.freedesktop.org/drm/amd/uploads/4af61751f8fa08340990b48824e4f9c5/amdgpu-ignore-min-pcap.patch"

echo "AMD-HOTFIX: Applying amdgpu-ignore_min_pcap patch..."
echo "Patch source: $PATCH_URL"
echo ""

if [ ! -f "$PATCH_FILE" ]; then
    echo "Patch file '$PATCH_FILE' not found."
    echo "Downloading patch from freedesktop.org..."
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$PATCH_FILE" "$PATCH_URL"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$PATCH_FILE" "$PATCH_URL"
    else
        echo "Error: Neither curl nor wget found to download the patch."
        echo "Please download manually from:"
        echo "  $PATCH_URL"
        exit 1
    fi
    
    if [ ! -f "$PATCH_FILE" ]; then
        echo "Error: Failed to download patch file."
        exit 1
    fi
    echo "Patch downloaded successfully."
    echo ""
fi

echo "Checking if patch can be applied..."
if patch --dry-run -p1 < "$PATCH_FILE"; then
    echo "Patch can be applied cleanly."
else
    echo "Warning: Patch may not apply cleanly. Trying with fuzz factor..."
    if ! patch -p1 --dry-run -F 3 < "$PATCH_FILE"; then
        echo "Error: Patch cannot be applied even with fuzz."
        echo "You may need to reset your git working directory."
        echo "Try: git restore . or git reset --hard"
        exit 1
    fi
fi

echo ""
echo "Applying patch..."
if patch -p1 < "$PATCH_FILE"; then
    echo "Patch applied successfully!"
    echo ""
    echo "To enable the feature, add 'amdgpu.ignore_min_pcap=1' to your kernel boot parameters."
    echo ""
    echo "Build the kernel with: make -j$(nproc)"
    echo "Install the kernel with your distribution's method."
else
    echo "Error: Patch failed to apply."
    echo ""
    echo "If the patch partially failed, you can reset with:"
    echo "  git restore ."
    echo "or"
    echo "  git reset --hard HEAD"
    exit 1
fi
