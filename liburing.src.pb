---
- hosts: all
  vars:
    REPO: https://github.com/axboe/liburing
    # Built from source (MAKE) rather than using the Debian liburing-dev
    # package: the Debian package bundles an io_uring.h that lacks the
    # zcrx UAPI (zcrx_ctrl_export, io_uring_query_zcrx, ...) that folly
    # HEAD needs, while upstream liburing's bundled copy carries it.
    # folly points at this install via CMAKE_PREFIX_PATH.
    MAKE: True
    MAKE_INSTALL_PREFIX: True
    # liburing's default `make` builds src + tests + examples; the `library`
    # target builds only liburing itself, which is all a dep consumer needs.
    MAKE_TARGET: library
  tasks:
    - import_tasks: tasks/compfuzor.includes
