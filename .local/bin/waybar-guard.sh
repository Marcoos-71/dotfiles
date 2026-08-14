#!/bin/bash
# Restarts waybar if it dies unexpectedly (upstream mpris/playerctl segfault).
# Stays out of the way when waybar was hidden on purpose via `omarchy toggle waybar`,
# which sets the waybar-off flag before killing the process.

WAYBAR_OFF="$HOME/.local/state/omarchy/toggles/waybar-off"

hidden_on_purpose() { [[ -f $WAYBAR_OFF ]]; }
running() { pgrep -x waybar >/dev/null; }

# Let the autostart waybar come up first so we never spawn a second bar.
sleep 15

while true; do
  if running || hidden_on_purpose; then
    sleep 5
    continue
  fi

  # Give `omarchy restart waybar` a chance to bring it back on its own.
  sleep 3
  if ! running && ! hidden_on_purpose; then
    setsid uwsm-app -- waybar >/dev/null 2>&1 &
  fi

  sleep 5
done
