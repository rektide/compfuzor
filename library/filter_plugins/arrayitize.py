import collections

listType = type(list())

def isList(*a):
    return isinstance(a, collections.Sequence) and not isinstance(a, basestring)

def arrayitize(*a, **kw):
    ''' Place passed in arguments into an array '''

    if len(a) is 1:
        if isinstance(a[0], basestring):
            return [a[0]]
        if isinstance(a[0], numbers.Number):
            return [a[0]]
        elif a[0] == True:
            return [True]
        elif a[0] == False:
            return [False]
        elif isList(a):
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
