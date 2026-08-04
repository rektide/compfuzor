"""defaultDir: prefix a relative path with a base directory.

``defaultDir(path, base)`` returns ``path`` unchanged when it is absolute
(starts with ``/`` or ``~``), otherwise returns ``base + "/" + path``.

Undefined or ``None`` path returns ``base`` unchanged — treat missing input
as "no basename, use the directory directly." This lets call sites drop
trailing fallbacks that existed only to keep the filter from raising on
undefined input.
"""

from ansible.errors import AnsibleError
from ansible.plugins.test.core import wrapped_test_undefined


def defaultDir(path, defaultDir=False):
    if path is None or wrapped_test_undefined(path):
        return defaultDir
    if not isinstance(path, str):
        raise AnsibleError(
            "defaultDir: path must be a string, got %s" % type(path).__name__
        )

    first = path[0]
    if first == "/" or first == "~":  # or (dotAbsolute and first == "."):
        return path
    else:
        if not defaultDir:
            raise AnsibleError(
                "defaultDir: no base directory provided for relative path %r" % path
            )
        if not isinstance(defaultDir, str):
            raise AnsibleError(
                "defaultDir: base must be a string, got %s" % type(defaultDir).__name__
            )
        return defaultDir + "/" + path


class FilterModule(object):
    def filters(self):
        return {
            "defaultDir": defaultDir
        }
