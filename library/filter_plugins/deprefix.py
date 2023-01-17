import re

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

def deregex(path, regex):
    found = re.search(regex, path)
    if found is None:
        return path
    return path[found.start(0):found.end(0)]

class FilterModule(object):
    def filters(self):
        return {
            "deprefix": deprefix,
            "depostfix": depostfix,
            "deregex": deregex
        }
