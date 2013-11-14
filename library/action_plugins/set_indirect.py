from ansible import utils
from ansible.runner.return_data import ReturnData

class ActionModule(object):

    NEEDS_TMPPATH = False

    def __init__(self, runner):
        self.runner = runner

    def run(self, conn, tmp, module_name, module_args, inject, complex_args=None, **kwargs):
        ''' handler for running operations on master '''

        options= utils.parse_kv(module_args)

        if not options['var']:
            return ReturnData(conn=conn, result=dict(failed= True, msg="No var specified"))

        k= options.get('var', None)
        v= options.get("val", None)
        if complex_args and v:
            v= complex_args[v]
        elif complex_args:
            v= complex_args
        elif not v:
            return ReturnData(conn=conn, result=dict(failed= True, msg="No val for "+k))

        result=dict({'ansible_facts':{k:v}})
        return ReturnData(conn=conn, result=result)
