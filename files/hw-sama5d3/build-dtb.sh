#!/bin/sh

[ -z "$LINUX_DIR" ] && LINUX_DIR="{{ LINUX_DIR|default(SRCS_DIR+'/linux') }}"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{OUTPUT_DIR}}"
[ -z "$BOARD" ] && BOARD="at91-sama5d3_xplained"

(cd "${LINUX_DIR}/arch/arm/boot/dts/"; dtc "${BOARD}.dts" -o "{{OUTPUT_DIR}}/${BOARD}.dtc" -O dtb)
