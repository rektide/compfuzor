#!/bin/bash
export ARCH=arm
export CROSS_COMPILE=arm-linux-gnueabi-
make tizen_artik5_defconfig
make exynos3250-artik5.dtb
make -j8 zImage
cat arch/arm/boot/zImage arch/arm/boot/dts/exynos3250-artik5.dtb > zImage
