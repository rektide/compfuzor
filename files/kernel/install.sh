for _cf_script in ${KERNEL_INSTALL_SCRIPTS:-}; do
  "$DIR/bin/${_cf_script}"
done
