for _cf_script in ${KERNEL_BUILD_SCRIPTS:-}; do
  "$DIR/bin/${_cf_script}"
done
