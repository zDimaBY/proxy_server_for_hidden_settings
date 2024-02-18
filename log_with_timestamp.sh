#!/bin/bash
while IFS= read -r line; do
    current_time=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$current_time: $line"
done
exit 0
