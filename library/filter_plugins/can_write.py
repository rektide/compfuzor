from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
from ansible import errors

def can_write(*a, **kw):
    return os.access(a[0], os.W_OK | os.X_OK)

class FilterModule(object):
    def filters(self):
        return {
            'can_write': can_write
        }
