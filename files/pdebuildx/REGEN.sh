#!/bin/sh
grep-available  -FPriority 'required' -sPackage > host.required
grep-available  -FPriority 'important' -sPackage > host.important
