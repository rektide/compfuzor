from __future__ import (absolute_import, division, print_function)
__metaclass__ = type

from ansible.errors import AnsibleError
from ansible.plugins.test import TestBase
from ansible.utils.display import Display
from jinja2 import pass_context

display = Display()

class TestModule(TestBase):

    def tests(self):
        return {
            'vars': self.vars_test,
            'vars_exists': self.vars_exists_test,
        }

    @pass_context
    def vars_test(self, context, item, prefix='', suffix=''):
        '''
        Look for variables in vars and hostvars[inventory_hostname]
        If item is a string, return the variable value if found
        If item is a list, filter to only values that are found
        prefix and suffix can be added to the item name
        '''
        # Get variables from the context
        all_vars = context.get('vars', {})
        
        # Get hostvars for the current host
        inventory_hostname = context.get('inventory_hostname')
        hostvars = context.get('hostvars', {}).get(inventory_hostname, {})
        
        # Add debugging
        display.vvv("vars_test: all_vars keys: %s" % list(all_vars.keys()))
        display.vvv("vars_test: hostvars keys for %s: %s" % (inventory_hostname, list(hostvars.keys())))
        display.vvv("vars_test: item: %s, prefix: '%s', suffix: '%s'" % (item, prefix, suffix))
        
        def lookup_var(name):
            # Apply prefix and suffix
            var_name = prefix + name + suffix
            display.vvv("vars_test: looking for variable: '%s'" % var_name)
            
            # First check in vars
            if var_name in all_vars:
                display.vvv("vars_test: found '%s' in all_vars: %s" % (var_name, all_vars[var_name]))
                return all_vars[var_name]
            # Then check in hostvars
            if var_name in hostvars:
                display.vvv("vars_test: found '%s' in hostvars: %s" % (var_name, hostvars[var_name]))
                return hostvars[var_name]
            display.vvv("vars_test: variable '%s' not found" % var_name)
            return None
        
        # Handle string input
        if isinstance(item, str):
            result = lookup_var(item)
            if result is not None:
                return result
            return False
        
        # Handle list input
        elif isinstance(item, list):
            # Return a list of booleans indicating if each variable exists
            results = []
            for name in item:
                result = lookup_var(name)
                results.append(result is not None)
            display.vvv("vars_test: list results: %s" % results)
            return results
        
        else:
            raise AnsibleError('vars test expects a string or list, got %s' % type(item))

    @pass_context
    def vars_exists_test(self, context, item, prefix='', suffix=''):
        '''
        Check if variables exist in vars and hostvars[inventory_hostname]
        Always returns a boolean, even for lists
        For lists, returns True only if ALL items are found
        prefix and suffix can be added to the item name
        '''
        # Get variables from the context
        all_vars = context.get('vars', {})
        
        # Get hostvars for the current host
        inventory_hostname = context.get('inventory_hostname')
        hostvars = context.get('hostvars', {}).get(inventory_hostname, {})
        
        # Add debugging
        display.vvv("vars_exists_test: all_vars keys: %s" % list(all_vars.keys()))
        display.vvv("vars_exists_test: hostvars keys for %s: %s" % (inventory_hostname, list(hostvars.keys())))
        display.vvv("vars_exists_test: item: %s, prefix: '%s', suffix: '%s'" % (item, prefix, suffix))
        
        def var_exists(name):
            # Apply prefix and suffix
            var_name = prefix + name + suffix
            display.vvv("vars_exists_test: checking existence of variable: '%s'" % var_name)
            exists = (var_name in all_vars) or (var_name in hostvars)
            display.vvv("vars_exists_test: variable '%s' exists: %s" % (var_name, exists))
            return exists
        
        # Handle string input
        if isinstance(item, str):
            result = var_exists(item)
            display.vvv("vars_exists_test: string result: %s" % result)
            return result
        
        # Handle list input
        elif isinstance(item, list):
            # Return True only if ALL items exist
            for name in item:
                if not var_exists(name):
                    display.vvv("vars_exists_test: list result: False (missing: %s)" % name)
                    return False
            display.vvv("vars_exists_test: list result: True")
            return True
        
        else:
            raise AnsibleError('vars_exists test expects a string or list, got %s' % type(item))
