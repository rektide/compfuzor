#!/bin/sh

LINUX="{{SRCS_DIR}}/{{kernel}}"
BOARD="at91-sama5d3_xplained"

(cd "${LINUX}/arch/arm/boot/dts/"; dtc "${BOARD.dts}" -o "{{DIR}}" -O dtb)
