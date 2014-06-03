#!/bin/sh

LINUX="{{SRCS_DIR}}/{{kernel}}"
BOARD="at91-sama5d3_xplained"
BIN="{{bin|default(item.bin)}}"

(cd "${LINUX}/arch/arm/boot/dts/"; dtc "${BOARD.dts}" -o "${BIN}" -O dtb)
