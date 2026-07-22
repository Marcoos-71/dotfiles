#!/bin/bash
reminder_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/omarchy-reminders"

timers=$(systemctl --user list-timers --all --no-legend --no-pager "omarchy-reminder-*.timer" 2>/dev/null | awk '{ print $(NF-1) }')

if [ -z "$timers" ]; then
    printf '{"text":"󰔛","class":"empty","tooltip":"Sin recordatorios"}\n'
    exit 0
fi

uptime_sec=$(awk '{ print int($1) }' /proc/uptime)
active_timers=()
active_msgs=()

while IFS= read -r timer; do
    next=$(systemctl --user show -P NextElapseUSecMonotonic "$timer" 2>/dev/null || true)
    [ -z "$next" ] && continue

    # Parse next elapse seconds (format: "2h 5min 3s" etc.)
    next_sec=0
    while read -r val unit; do
        int_val=${val%.*}
        case $unit in
            d)   next_sec=$((next_sec + int_val * 86400)) ;;
            h)   next_sec=$((next_sec + int_val * 3600))  ;;
            min) next_sec=$((next_sec + int_val * 60))    ;;
            s)   next_sec=$((next_sec + int_val))         ;;
        esac
    done < <(grep -oE '[0-9]+([.][0-9]+)?(d|h|min|s)' <<<"$next" | sed -E 's/([0-9.]+)([a-z]+)/\1 \2/')

    (( next_sec <= uptime_sec )) && continue

    remaining=$((next_sec - uptime_sec))
    mins=$((remaining / 60))
    secs=$((remaining % 60))

    unit_base="${timer%.timer}"
    msg_file="$reminder_dir/$unit_base.message"

    if [ -f "$msg_file" ]; then
        msg=$(cat "$msg_file" | head -c 40 | tr '"' "'")
    else
        reminder_mins=$(echo "$unit_base" | grep -oP '\d+(?=m-)')
        msg="${reminder_mins}m reminder"
    fi

    if (( mins > 0 )); then
        remaining_str="${mins}m ${secs}s"
    else
        remaining_str="${secs}s"
    fi

    active_timers+=("$timer")
    active_msgs+=("$msg ($remaining_str)")
done <<< "$timers"

count=${#active_timers[@]}

if (( count == 0 )); then
    printf '{"text":"󰔛","class":"empty","tooltip":"Sin recordatorios"}\n'
    exit 0
fi

first_msg="${active_msgs[0]}"
tooltip=$(printf '%s\n' "${active_msgs[@]}" | tr '\n' '|' | sed 's/|$//' | sed 's/|/\\n/g')

if (( count > 1 )); then
    text="󰔛 $first_msg  +$((count - 1)) más"
else
    text="󰔛 $first_msg"
fi

printf '{"text":"%s","class":"active","tooltip":"%s"}\n' "$text" "$tooltip"
