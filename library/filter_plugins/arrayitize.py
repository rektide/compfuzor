def arrayitize(*a, **kw):
    ''' Place passed in arguments into an array '''
    if len(a) is 1:
        if  type(a[0]) is list:
            return a
        elif a[0] is None:
            return []
    val = []
    for el in a:
        val.append(el)
    return val

class FilterModule(object):
    ''' Compfuzor jinja2 filters '''

    def filters(self):
        return {
            'arrayitize': arrayitize
        }
