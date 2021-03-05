#!/bin/bash

status_dir=/var/bigbluebutton/recording/status/published
scripts_dir=/usr/local/bigbluebutton/core/scripts
work_dir=/var/bigbluebutton/recording/scalelite

if ! sudo -n -u bigbluebutton true; then
    echo "Unable to run commands as the bigbluebutton user, try running this script as root"
    exit 1
fi

prev_record_id=
for done_file in "$status_dir"/*.done; do
    record_id="${done_file##*/}"
    record_id="${record_id%-*.done}"
    if [[ $record_id = $prev_record_id ]]; then continue; fi
    
    prev_record_id="$record_id"
    
    if [[ -f "$work_dir/copied/$record_id" ]]; then continue; fi
    
    ( cd "$scripts_dir" && sudo -n -u bigbluebutton ruby ./post_publish/scalelite_post_publish.rb -m "$record_id" )
done
