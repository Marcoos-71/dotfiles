#!/bin/bash
SINK=$(pactl get-default-sink 2>/dev/null)
VOL=$(pactl get-sink-volume "$SINK" 2>/dev/null | grep -oP '\d+(?=%)' | head -1)
MUTED=$(pactl get-sink-mute "$SINK" 2>/dev/null | awk '{print $2}')

VOL=${VOL:-0}
[ "$VOL" -gt 100 ] && VOL=100

FILLED=$(( VOL / 10 ))
[ "$FILLED" -gt 10 ] && FILLED=10
EMPTY=$(( 10 - FILLED ))

BAR=""
for _ in $(seq 1 "$FILLED" 2>/dev/null); do BAR="${BAR}█"; done
for _ in $(seq 1 "$EMPTY" 2>/dev/null); do BAR="${BAR}░"; done

if [ "$MUTED" = "yes" ]; then
    echo "{\"text\": \"󰝟  ░░░░░░░░░░ muted\", \"class\": \"muted\", \"tooltip\": \"Silenciado (${VOL}%)\"}"
elif [ "$VOL" -lt 34 ]; then
    echo "{\"text\": \"󰕿 ${BAR} ${VOL}%\", \"class\": \"low\", \"tooltip\": \"Volumen: ${VOL}%\"}"
elif [ "$VOL" -lt 67 ]; then
    echo "{\"text\": \"󰖀 ${BAR} ${VOL}%\", \"class\": \"mid\", \"tooltip\": \"Volumen: ${VOL}%\"}"
else
    echo "{\"text\": \"󰕾 ${BAR} ${VOL}%\", \"class\": \"high\", \"tooltip\": \"Volumen: ${VOL}%\"}"
fi
