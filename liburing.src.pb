---
- hosts: all
  vars:
    REPO: https://git.kernel.dk/liburing
    # Built from source (MAKE_AUTOCONF) rather than using the Debian
    # liburing-dev package: the Debian package bundles an io_uring.h that
    # lacks the zcrx UAPI (zcrx_ctrl_export, io_uring_query_zcrx, ...) that
    # folly HEAD needs, while upstream liburing's bundled copy carries it.
    # folly points at this install via CMAKE_PREFIX_PATH.
    MAKE_AUTOCONF: True
  tasks:
    - import_tasks: tasks/compfuzor.includes
