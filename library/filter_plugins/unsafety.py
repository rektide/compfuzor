from __future__ import (absolute_import, division, print_function)
__metaclass__ = type


from ansible._internal._datatag import _tags

def unsafety( *a, **kw):
    return _tags.TrustedAsTemplate().tag(a[0])

class FilterModule(object):
    def filters(self):
        return {
                'unsafety': unsafety
        }
