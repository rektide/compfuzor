import re
def remove_prefix(text, prefix):
    return re.sub(r'^{0}'.format(re.escape(prefix)), '', text)

def deprefix(path, prefixRegex):
    found = re.search('^' + prefixRegex, path)
    if found is None:
        return path
    searchLen = len(found.group(0))
    return path[searchLen:]

def depostfix(path, prefixRegex):
    found = re.search(prefixRegex + '$', path)
    if found is None:
        return path
    searchLen = len(found.group(0)) + 1
    return path[:searchLen]

class FilterModule(object):
    def filters(self):
        return {
            "deprefix": deprefix,
            "depostfix": depostfix
        }
