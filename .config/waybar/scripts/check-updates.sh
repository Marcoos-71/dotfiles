#!/bin/bash

# Shows in waybar only when there's something worth updating:
# - Omarchy has a new version
# - A CVE affects an installed package (arch-audit)
# - A critical package has an update (linux, mesa, systemd, glibc, openssl)

CRITICAL=(linux mesa systemd glibc openssl)

messages=()
tooltip_lines=()
has_update=false

# 1. Omarchy update
omarchy_out=$(omarchy-update-available 2>/dev/null)
if [[ $? -eq 0 ]]; then
    messages+=("Omarchy")
    tooltip_lines+=("$omarchy_out")
    has_update=true
fi

# 2. Security vulnerabilities
if command -v arch-audit &>/dev/null; then
    vuln=$(arch-audit --quiet 2>/dev/null)
    if [[ -n "$vuln" ]]; then
        count=$(echo "$vuln" | wc -l)
        messages+=("${count} CVE(s)")
        while IFS= read -r line; do
            tooltip_lines+=("⚠ $line")
        done <<< "$vuln"
        has_update=true
    fi
fi

# 3. Critical package updates
if command -v checkupdates &>/dev/null; then
    available=$(checkupdates 2>/dev/null)
    for pkg in "${CRITICAL[@]}"; do
        if echo "$available" | grep -q "^${pkg} "; then
            line=$(echo "$available" | grep "^${pkg} ")
            messages+=("$pkg")
            tooltip_lines+=("󰚰 $line")
            has_update=true
        fi
    done
fi

$has_update || exit 1

text="󰚰 $(IFS=', '; echo "${messages[*]}")"
tooltip=$(printf '%s\n' "${tooltip_lines[@]}" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"text": "%s", "tooltip": "%s"}\n' "$text" "${tooltip//$'\n'/\\n}"
