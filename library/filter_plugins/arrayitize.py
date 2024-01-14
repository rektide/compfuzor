import collections
import numbers
from six import string_types

listType = type(list())

def isList(*a):
    return isinstance(a, collections.abc.Sequence) and not isinstance(a, string_types)

def arrayitize(*a, **kw):
    ''' Place passed in arguments into an array '''

    if len(a) == 1:
        if isinstance(a[0], string_types):
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
