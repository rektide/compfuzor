from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
import pwd
import grp
import types
from ansible import errors

NumberTypes = (types.IntType, types.LongType, types.FloatType)

def to_uid( arg):
    return arg if isinstance( arg, NumberTypes) else pwd.getpwnam( arg).pw_uid

def to_gid( arg):
    return arg if isinstance( arg, NumberTypes) else grp.getgrnam( arg).gr_gid 

def diff_user( *a, **kw):
    u_req = to_uid( a[0])
    u_cur = to_uid( a[1])
    if u_req != u_cur:
        return True
    # check gid too
    if len(a) > 2:
        g_req = to_gid( a[2])
        g_cur = to_gid( a[3])
        if g_req != g_cur:
            return True
    return False

class FilterModule(object):
    def filters(self):
        return {
            'diff_user': diff_user,
			'to_uid': to_uid,
			'to_gid': to_gid
        }
