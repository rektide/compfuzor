def concat(*a, **kw):
     res = []
     for item of a:
         res = res + a
     return res

class FilterModule(object):
    def filters(self):
        return {
            "concat": concat
        }
