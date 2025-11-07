from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.errors import AnsibleError
from ansible.plugins.test import TestBase
from ansible.utils.display import Display

display = Display()

class TestModule(TestBase):

    def tests(self):
        return {
            'vars': self.vars_test,
        }

    def vars_test(self, item, prefix='', suffix=''):
        '''
        Look for variables in vars and hostvars[inventory_hostname]
        If item is a string, return the variable value if found
        If item is a list, filter to only values that are found
        prefix and suffix can be added to the item name
        '''
        # Get the task variables
        if not hasattr(self, '_templar'):
            raise AnsibleError('Templar not available')
        
        # Get variables from the templar
        all_vars = self._templar.available_variables
        
        # Get hostvars for the current host
        inventory_hostname = all_vars.get('inventory_hostname')
        hostvars = all_vars.get('hostvars', {}).get(inventory_hostname, {})
        
        # Look in both 'vars' and hostvars
        # 'vars' is typically from group_vars or other variable sources
        vars_dict = all_vars.get('vars', {})
        
        def lookup_var(name):
            # Apply prefix and suffix
            var_name = prefix + name + suffix
            
            # First check in vars
            if var_name in vars_dict:
                return vars_dict[var_name]
            # Then check in hostvars
            if var_name in hostvars:
                return hostvars[var_name]
            return None
        
        # Handle string input
        if isinstance(item, str):
            result = lookup_var(item)
            if result is not None:
                return result
            return False
        
        # Handle list input
        elif isinstance(item, list):
            results = []
            for name in item:
                result = lookup_var(name)
                if result is not None:
                    results.append(result)
            return results
        
        else:
            raise AnsibleError('vars test expects a string or list, got %s' % type(item))
