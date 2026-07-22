#!/bin/bash
IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}')
[ -z "$IFACE" ] && echo '{"text": "󰖪 —"}' && exit 0

CACHE="/tmp/waybar-netspeed-${IFACE}"
rx_now=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes" 2>/dev/null || echo 0)
tx_now=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes" 2>/dev/null || echo 0)
time_now=$(date +%s%N)

fmt() {
    local kbps=$1
    if [ "$kbps" -ge 1024 ]; then
        awk "BEGIN {printf \"%.1fM\", $kbps/1024}"
    elif [ "$kbps" -ge 1 ]; then
        echo "${kbps}K"
    else
        echo "0K"
    fi
}

if [ -f "$CACHE" ]; then
    IFS=' ' read -r rx_prev tx_prev time_prev < "$CACHE"
    elapsed=$(( time_now - time_prev ))
    [ "$elapsed" -le 0 ] && elapsed=1000000000

    rx_kbps=$(( (rx_now - rx_prev) * 1000000000 / elapsed / 1024 ))
    tx_kbps=$(( (tx_now - tx_prev) * 1000000000 / elapsed / 1024 ))

    DOWN=$(fmt "$rx_kbps")
    UP=$(fmt "$tx_kbps")

    printf '{"text":"󰁻 %s 󰁹 %s","tooltip":"Interfaz: %s\\n↓ %s/s  ↑ %s/s"}\n' \
        "$DOWN" "$UP" "$IFACE" "$DOWN" "$UP"
else
    printf '{"text":"󰁻 — 󰁹 —"}\n'
fi

echo "$rx_now $tx_now $time_now" > "$CACHE"
