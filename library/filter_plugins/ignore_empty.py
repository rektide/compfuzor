def ignore_empty(o):
	return { k: v for k,v in o.items() if v != None and v != '' }

class FilterModule(object):
    def filters(self):
        return {
            'ignore_empty': ignore_empty 
        }
