from __future__ import absolute_import, division, print_function

__metaclass__ = type

from ansible.errors import AnsibleError
from ansible.utils.display import Display
from jinja2 import pass_context

display = Display()


class FilterModule(object):
    def filters(self):
        return {
            "has_var": self.vars_filter,
            "has_vars": self.vars_filter,
        }

    @pass_context
    def vars_filter(
        self,
        context,
        item,
        prefix="",
        suffix="",
        returnLookedup=None,
        upper=False,
        lower=False,
    ):
        """
        Look for variables in vars and hostvars[inventory_hostname]
        If item is a string, return the variable value if found
        If item is a list, filter to only values that are found
        prefix and suffix can be added to the item name
        """
        # Get variables from the context
        all_vars = context.get("vars", {})

        # Get hostvars for the current host
        inventory_hostname = context.get("inventory_hostname")
        hostvars = context.get("hostvars", {}).get(inventory_hostname, {})

        # Add debugging
        display.vvv("vars_filter: all_vars keys: %s" % list(all_vars.keys()))
        display.vvv(
            "vars_filter: hostvars keys for %s: %s"
            % (inventory_hostname, list(hostvars.keys()))
        )
        display.vvv(
            "vars_filter: item: %s, prefix: '%s', suffix: '%s'" % (item, prefix, suffix)
        )

        def lookup_var(name):
            # Apply prefix and suffix
            var_name = prefix + name + suffix
            if upper:
                var_name = var_name.upper()
            if lower:
                var_name = var_name.lower()
            display.vvvvv("vars_filter: looking for variable: '%s'" % var_name)

            # First check in hostvars
            if var_name in hostvars:
                display.vvvvv(
                    "vars_filter: found '%s' in hostvars: %s"
                    % (var_name, hostvars[var_name])
                )
                return hostvars[var_name]
            # Then check in vars
            if var_name in all_vars:
                display.vvvvv(
                    "vars_filter: found '%s' in all_vars: %s"
                    % (var_name, all_vars[var_name])
                )
                return all_vars[var_name]

            display.vvv("vars_filter: variable '%s' not found" % var_name)
            return None

        # Handle string input
        if isinstance(item, str):
            if returnLookedup is None:
                returnLookedup = True

            result = lookup_var(item)
            if result is None:
                return False
            elif returnLookedup:
                return result
            else:
                return item

        # Handle list input
        elif isinstance(item, list):
            if returnLookedup is None:
                returnLookedup = False  # just t/f

            # Return a list of booleans indicating if each variable exists
            results = []
            for name in item:
                result = lookup_var(name)
                display.vvvvv(
                    "vars_filter: list step: %s %s" % (result, result is None)
                )
                if result is None:
                    display.vvvvv("SKIP")
                elif returnLookedup:
                    display.vvvvv("X")
                    results.append(result)
                else:
                    display.vvvvv("Y")
                    results.append(name)

            display.vvvvv("vars_filter: list results: %s" % results)
            return results
        else:
            raise AnsibleError(
                "vars test expects a string or list, got %s" % type(item)
            )
