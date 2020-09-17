import collections
import numbers

def listify(*a, **kw):

    if isinstance(a[0], dict):
        return [ {"key": k, "value": a[0][k] } for k in a[0] ]
    return a[0]
   
class FilterModule(object):
    ''' Compfuzor jinja2 filters '''

    def filters(self):
        return {
            'listify': listify
        }
