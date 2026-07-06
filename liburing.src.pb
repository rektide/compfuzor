---
- hosts: all
  vars:
    REPO: https://git.kernel.dk/liburing
    # Built from source rather than using the Debian liburing-dev package:
    # the Debian package bundles an io_uring.h that lacks the zcrx UAPI
    # (zcrx_ctrl_export, io_uring_query_zcrx, ...) that folly HEAD needs,
    # while upstream liburing's bundled copy carries it. Installing to
    # ${DIR} lets folly point at it via CMAKE_PREFIX_PATH.
    BINS:
      - name: build.sh
        run: True
        basedir: repo
        content: |
          ./configure --prefix="${DIR}"
          make -j"$(nproc)"
          make install
  tasks:
    - import_tasks: tasks/compfuzor.includes
