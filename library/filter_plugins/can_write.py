from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
import pwd
import grp
#import types
from ansible import errors

#NumberTypes = (types.IntType, types.LongType, types.FloatType)
NumberTypes = (int, float)

def good(arg):
    return arg is not None and arg != ""

def to_uid( arg):
    return arg if isinstance( arg, NumberTypes) else pwd.getpwnam( arg).pw_uid

def to_gid( arg):
    return arg if isinstance( arg, NumberTypes) else grp.getgrnam( arg).gr_gid

def diff_user( *a, **kw):
    if good(a[0]) and good(a[1]):
        u_req = to_uid( a[0])
        u_cur = to_uid( a[1])
        if u_req != u_cur:
            return True
    # check gid too
    if len(a) > 2 and good(a[2]) and good(a[3]):
        g_req = to_gid( a[2])
        g_cur = to_gid( a[3])
        if g_req != g_cur:
            return True
    return False

def has_write( *a, **kw):
    path = a[0]
    return os.access( path, os.W_OK)

# os.access checks in current user's access, not target users boo
# we really need to know if we can write this. should_become checks for mismatching users separately!
def can_write( *a, **kw):
    path = a[0]

    exists = os.access( path, os.F_OK)

    if not exists:
        aParentList = list( a)
        aParentList[0] = os.path.dirname( path)
        aParent = tuple(aParentList)
        return can_write(*aParent, **kw)

    return os.access( path, os.W_OK)

def should_become( *a):
    # check user and group
    if len(a) >= 4:
        if diff_user( a[1], a[2], a[3], a[4]):
            return True
    # check group
    elif len(a) >= 2:
        if diff_user( a[1], a[2]):
            return True

    # check write
    if len(a) >= 4:
        return not can_write( a[0], a[1], a[3])
    elif len(a) >= 2:
        return not can_write( a[0], a[1])
    else:
        return not can_write( a[0])

class FilterModule(object):
    def filters(self):
        return {
            'should_become': should_become,
            'has_write': has_write,
            'can_write': can_write,
            'diff_user': diff_user,
            'to_uid': to_uid,
            'to_gid': to_gid
        }
