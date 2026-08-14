#!/bin/bash

output() {
    # Small delay to ensure Hyprland updates the state before we query it
    sleep 0.1
    
    # Get the active layout index using hyprctl
    ACTIVE_INDEX=$(hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .active_layout_index // -1')

    case "$ACTIVE_INDEX" in
        0)
            DISPLAY_TEXT="🇺🇸"
            CLASS="en"
            ;;
        1)
            DISPLAY_TEXT="🇷🇺"
            CLASS="ru"
            ;;
        *)
            DISPLAY_TEXT="??"
            CLASS="unknown"
            ;;
    esac

    printf '{"text":"%s","class":"%s"}\n' "$DISPLAY_TEXT" "$CLASS"
}

# Initial output
output

# Listen for the SIGRTMIN+1 signal
trap 'output' SIGRTMIN+1

while true; do
    sleep infinity & wait $!
done