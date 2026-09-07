#!/bin/bash
# Shows network transfer speed only during active file transfers (rsync, scp, sftp, or high throughput)

CACHE=/tmp/waybar-transfer-cache
THRESHOLD=2097152  # 2 MB/s — por encima de esto se considera transferencia

# Detectar interfaz activa
IFACE=$(ip route 2>/dev/null | awk '/^default/ { print $5; exit }')
[ -z "$IFACE" ] && IFACE=wlan0

# Leer bytes actuales
read -r cur_rx cur_tx <<< "$(awk -v dev="${IFACE}:" '$1==dev { print $2, $10 }' /proc/net/dev)"
now=$(date +%s%3N)

format_speed() {
    awk -v b="$1" 'BEGIN {
        if (b >= 1048576)      printf "%.1f MB/s", b/1048576
        else if (b >= 1024)   printf "%d KB/s", b/1024
        else                  printf "%d B/s", b
    }'
}

# Detectar si hay proceso de transferencia activo
has_process() {
    pgrep -x rsync > /dev/null 2>&1 && return 0
    pgrep -x scp   > /dev/null 2>&1 && return 0
    pgrep -x sftp  > /dev/null 2>&1 && return 0
    pgrep -x rclone > /dev/null 2>&1 && return 0
    return 1
}

if [ -f "$CACHE" ]; then
    read -r prev_rx prev_tx prev_time <<< "$(cat "$CACHE")"
    elapsed=$(( now - prev_time ))

    if [ "$elapsed" -gt 0 ] && [ -n "$prev_rx" ]; then
        rx_speed=$(( (cur_rx - prev_rx) * 1000 / elapsed ))
        tx_speed=$(( (cur_tx - prev_tx) * 1000 / elapsed ))
        total=$(( rx_speed + tx_speed ))

        if has_process || [ "$total" -gt "$THRESHOLD" ]; then
            rx_fmt=$(format_speed "$rx_speed")
            tx_fmt=$(format_speed "$tx_speed")
            printf '{"text": "󰇚 %s  󰕒 %s", "class": "active", "tooltip": "Transferencia activa\n↓ %s  ↑ %s"}\n' \
                "$rx_fmt" "$tx_fmt" "$rx_fmt" "$tx_fmt"
        else
            echo '{"text": "", "class": "inactive"}'
        fi
    else
        echo '{"text": "", "class": "inactive"}'
    fi
else
    echo '{"text": "", "class": "inactive"}'
fi

echo "$cur_rx $cur_tx $now" > "$CACHE"
