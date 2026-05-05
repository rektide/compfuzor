from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
from ansible.utils.display import Display

display = Display()


class LookupModule(LookupBase):
    def run(self, terms, variables=None, **kwargs):
        want_truthy = kwargs.get("truthy", False)
        if variables is None:
            raise AnsibleError("vardefined lookup requires variables context")
        names = terms if isinstance(terms, (list, tuple)) else [terms]
        for name in names:
            name = str(name)
            if name not in variables:
                continue
            if not want_truthy:
                return [True]
            val = variables[name]
            if val is not None and val is not False and val != "" and val != 0:
                return [True]
        return [False]
