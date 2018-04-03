def defaultDir(path, defaultDir):
    first = path[0]
    if first == "/" or first == "~":
        return path
    else:
        if not defaultDir:
            raise "NoDefaultDir"
        return defaultDir + "/" + path

class FilterModule(object):
    def filters(self):
        return {
            "defaultDir": defaultDir
        }
