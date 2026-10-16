"""Recursive Jinja template rendering for Ansible data trees.

Walks a structure and renders any string containing ``{{`` through the Jinja
environment using the current variable scope (including task vars and loop
vars). Non-strings and strings without template markers pass through unchanged.

This is the rendering counterpart to ``template_data.py``'s raw-data access:
where ``template_data`` defers rendering for safe traversal, this module forces
rendering so template strings nested inside dicts/lists/tuples resolve to
their final values at the current scope.

Caveat (ansible-core >= 2.19): re-rendering from inside a running filter
evaluation trips the marker/deferral machinery in rich task scopes (the
manual render raises ``MarkerError``, which the fall-through below silently
swallows -- a no-op). For values that must be rendered NOW, prefer
``lookup('template_value', ...)``, which re-enters the task-level templar
the way lookups are designed to; gen_zim.tasks uses it for declaration
values and ``zim_fragment`` rejects any marker that survives.

Ansible filter exposed:
    ``resolve``  -- recursively render template strings in a value.

Typical use::

    # Render template strings inside a YAML literal dict before it leaves
    # the task scope (so the stored fact doesn't carry task-local refs):
    _etc_entry: "{{ {'name': 'foo', 'content': _local_var} | resolve }}"

    # Equivalent inside a merge_list call:
    BINS: "{{ BINS | merge_list(_item, preset='bins_generated', resolve=True) }}"

Related modules:
    ``template_data``  -- raw data-access helpers (non-rendering).
    ``cfmerge``        -- consumes ``render_templates`` via ``merge_list(resolve=True)``.
    ``template_value`` -- the lookup that renders reliably on 2.19+.
"""

from __future__ import absolute_import, division, print_function

from jinja2 import pass_context

__all__ = ["render_templates"]


@pass_context
def render_templates(context, value):
    """Recursively render Jinja template strings using the evaluation context.

    Strings containing ``{{`` are rendered via the Jinja environment with the
    current variable scope (including loop variables). Non-strings and strings
    without template markers pass through unchanged. Render errors fall through
    to the original value (so a missing var doesn't crash the walk).

    Use this when a value contains template strings referencing variables that
    won't be in scope during later rendering passes -- e.g. task-local vars
    embedded in a dict literal that ansible stores lazily and re-renders later
    (often inside ``fs_hierarchy`` or another downstream task).

    Args:
        context: Jinja evaluation context (injected by ``@pass_context``).
        value: Any Ansible/Jinja value. Container types are walked; strings
            containing ``{{`` are rendered; everything else passes through.

    Returns:
        A plain container tree with template strings resolved at this scope.
    """
    if isinstance(value, str) and "{{" in value:
        # get_all() is the public Jinja API for the full variable scope
        # (globals + locals). The legacy internal "vars" dict is deprecated
        # (removal slated for ansible-core 2.24) and returned empty in var
        # evaluation contexts, which silently disabled rendering.
        variables = context.get_all()
        if variables:
            try:
                return context.environment.from_string(value).render(**variables)
            except Exception:
                return value
    if isinstance(value, dict):
        return {k: render_templates(context, v) for k, v in value.items()}
    if isinstance(value, list):
        return [render_templates(context, v) for v in value]
    if isinstance(value, tuple):
        return tuple(render_templates(context, v) for v in value)
    return value


class FilterModule(object):
    """Expose the ``resolve`` filter to Ansible's filter-plugin loader."""

    def filters(self):
        return {
            "resolve": render_templates,
        }
