import re


def ansible_cmdline(cmdline):
    """
    Parse /proc/cmdline to find first argument matching <type>.<instance>.pb pattern.

    Args:
        cmdline (str): Command line string

    Returns:
        dict: Object with 'type' and 'instance' keys, or empty dict if no match
    """
    if not cmdline:
        return {}

    # Pattern to match <type>.<instance>.pb
    pattern = r"(\w+)\.(\w+)\.pb"

    # Split cmdline into arguments (handling quoted arguments)
    import shlex

    try:
        args = shlex.split(cmdline)
    except:
        # Fallback to simple split if shlex fails
        args = cmdline.split()

    # Search for pattern in each argument
    for arg in args:
        match = re.search(pattern, arg)
        if match:
            return {"type": match.group(1), "instance": match.group(2)}

    return {}


class FilterModule(object):
    """Compfuzor jinja2 filters"""

    def filters(self):
        return {"ansible_cmdline": ansible_cmdline}
