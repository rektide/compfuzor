import collections

listType = type(list())

def isList(*a):
    return isinstance(a, collections.Sequence) and not isinstance(a, basestring)

def arrayitize(*a, **kw):
    ''' Place passed in arguments into an array '''
    if len(a) is 1:
        if isList(a):
            return a[0]
        elif a[0] is None:
            return []
    val = []
    for el in a:
        if isList(el):
            val = val + el
        else:
            val.append(el)
    return val

class FilterModule(object):
    ''' Compfuzor jinja2 filters '''

    def filters(self):
        return {
            'arrayitize': arrayitize
        }
