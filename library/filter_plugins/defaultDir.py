def defaultDir(path, defaultBase):
    first = path[0]
    if first == "/" or first == "~":
        return path
    else:
        return defaultBase + "/" + path

class FilterModule(object):
    def filters(self):
        return {
            'defaultDir': defaultDir
        }
