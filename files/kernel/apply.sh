for _cf_script in ${KERNEL_APPLY_SCRIPTS:-}; do
  "$DIR/bin/${_cf_script}"
done
