from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
from ansible import errors

def can_write( *a, **kw):
    path = a[ 0]
    mod = os.W_OK
    if not os.access( a[0], os.F_OK):
        path = os.path.dirname( a[0])
        mod |= os.X_OK
    return os.access( path, mod)

class FilterModule(object):
    def filters(self):
        return {
            'can_write': can_write
        }
