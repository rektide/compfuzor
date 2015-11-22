#!/bin/sh

[ -z "$BOARD" ] && BOARD="{{BOARD}}"
[ -z "$OUTPUT_DIR" ] && OUTPUT_DIR="{{OUTPUT_DIR}}"

cp arch/arm/boot/{zImage,uImage,dts/$BOARD.dt{b,s}} $OUTPUT_DIR/
