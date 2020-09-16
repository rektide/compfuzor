from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

import collections

from ansible.errors import AnsibleError
from ansible.plugins.lookup import LookupBase
class LookupModule(LookupBase):
    def run(self, terms, varibles=None, **kwargs):

	print (terms)

        # FIXME: can remove once with_ special case is removed
        if isinstance(terms, list):
            return terms

        results = []
        for term in terms:

            results.append({ "key": term, "value": terms[term] })
        print (results)
        return results
