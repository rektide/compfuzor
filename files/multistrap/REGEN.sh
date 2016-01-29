#!/bin/sh

# via: http://wiki.debian.org/Multistrap#Package_selection_by_Priority
grep-available  -FPriority 'required' -sPackage > host.required
grep-available  -FPriority 'important' -sPackage > host.important
