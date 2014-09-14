#!/bin/sh

for prefs in $HOME/.config/spotify/Users/*/prefs ;
do
	echo "pref $prefs"
	echo "ui.track_notifications_enabled=false" >> $prefs
done
