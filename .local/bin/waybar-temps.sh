#!/bin/bash
CPU=$(sensors 2>/dev/null | awk '/Tctl:/ {gsub(/[+°C]/,"",$2); print $2}')
GPU=$(sensors 2>/dev/null | awk '/^edge:/ {gsub(/[+°C]/,"",$2); print $2}')

CPU=${CPU:-"?"}
GPU=${GPU:-"?"}

CLASS=$(awk -v cpu="$CPU" 'BEGIN {
    if (cpu == "?") print "good"
    else if (cpu+0 > 80) print "critical"
    else if (cpu+0 > 65) print "warning"
    else print "good"
}')

echo "{\"text\": \"󰔏 ${CPU}°/${GPU}°\", \"tooltip\": \"CPU: ${CPU}°C  ·  GPU: ${GPU}°C\", \"class\": \"$CLASS\"}"
