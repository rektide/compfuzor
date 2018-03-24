from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import os
import pwd
import grp
import types
from ansible import errors

NumberTypes = (types.IntType, types.LongType, types.FloatType)

def can_write( *a, **kw):
    path = a[0]
    exists = os.access( path, os.F_OK)
    dirpath = os.path.dirname( path)
    # can we write the directory? needed if we need to (re-)constitute
    if not os.access( dirpath, os.W_OK):
        return False
    # now check - exists but not writable
    if exists and  not os.access( path, os.W_OK):
        return False
    # optional user/uid passed in?
    if len(a) >= 2:
        # check permissions on file
        if not exists:
            return True
        arg_uid = a[1]
        uid = arg_uid if isinstance( arg_uid, NumberTypes) else pwd.getpwnam( arg_uid).pw_uid
        stat = os.lstat( path)
        if uid != stat.st_uid:
            return False
        # optional group/gid passed in?
        if len(a) >= 3:
            arg_gid = a[2]
            gid = arg_gid if isinstance( arg_gid, NumberTypes) else grp.getgrnam( arg_gid).gr_gid 
            if gid != stat.st_gid:
                return False
    return True

class FilterModule(object):
    def filters(self):
        return {
            'can_write': can_write
        }
