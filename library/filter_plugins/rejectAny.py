def rejectAny(*a, **kw):
    return (n for n in a[0] if n not in a[1])

class FilterModule(object):
    def filters(self):
        return {
            "rejectAny": rejectAny
        }
