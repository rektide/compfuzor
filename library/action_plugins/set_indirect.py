from ansible import utils
from ansible.runner.return_data import ReturnData

class ActionModule(object):

    NEEDS_TMPPATH = False

    def __init__(self, runner):
        self.runner = runner

    def run(self, conn, tmp, module_name, module_args, inject, complex_args=None, **kwargs):
        ''' handler for running operations on master '''

        # load up options
        options  = {}
        if complex_args:
            options.update(complex_args)
        options.update(utils.parse_kv(module_args))
        result=dict({'ansible_facts':{options['var']: options['val']}})

        return ReturnData(conn=conn, result=result)
