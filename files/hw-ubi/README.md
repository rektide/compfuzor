# HW-UBI

Kitchen sink of tools for taking a OS image and writing to embedded targets. The production end-to-end workflow of this kit uses already-installed uboot or mtd-utils tools to burn the kit's output target: new uboot and OS images. The development workflow provides additional OpenOCD using targets.

Accepts a bootstrapped archive image as in. Generator for an OpenOCD executor, customized uboot build, customized FDT DTB, ubi image. All outputs are in var subdirectory. Configs are stored in etc, build scripts generate in bin. Working space (extracted bootstrap archive image) is in var/dist.

Ideally openocd is unnecessary and all flashing can be done via uboot.  In practice, 

* extract-image
* **OpenOCD**
  * Stored configs
  * `start-openocd` - open connection to hardware
* **UBoot**
  * Store custom board configs for uboot
  * `build-uboot`
  * `install-uboot` - flash uboot via openocd
  * (Flash uboot via uboot, mtd-utils)
* **Flattened Device Tree (FDT)**
  * Store custom configs for Device Tree Source (DTS)
  * `build-dtb` - build kernel Device Tree Binary (DTB)'s from DTS
  * `install-dtb` - install a DTB into local working space
* **UBI/UBIFS**
  * Symlink to a local image archive, extract locally
  * `build-ubifs` a ubifs filesystem
  * `build-ubi` a ubi image
  * `split` image into chunk-sized pieces
  * (Flash ubi image, via uboot & openocd, mtd-utils)
* **Tftp**
  * Link var resources for tftpd use
  * Install `tftpd-hpa` package


# Support Matrix

| hw\image |            | uboot   | --v   | --v      | ubi     | --v   | --v      |
|----------|------------|---------|-------|----------|---------|-------|----------|
|          | \image via | openocd | uboot | mtd-util | openocd | uboot | mtd-util |
| iconnect |            | x       |       |          |         |       |          |
