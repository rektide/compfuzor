#from jinja2.filters import pass_environment

#@pass_environment
#def defaultDir(environment, path, defaultDir=False):
def defaultDir(path, defaultDir=False):
    #if not defaultDir:
    #    defaultDir = 'files/' + environment.globals["TYPE"]

    first = path[0]
    if first == "/" or first == "~":  # or (dotAbsolute and first == "."):
        return path
    else:
        if not defaultDir:
            raise "NoDefaultDir"
        if not isinstance(defaultDir, str):
            raise "Need string defaultDir"
        if not isinstance(path, str):
            raise "Need string path"
        return defaultDir + "/" + path

class FilterModule(object):
    def filters(self):
        return {
            "defaultDir": defaultDir
        }
