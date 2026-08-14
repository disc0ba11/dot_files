#!/usr/bin/env bash

# 1. Get the current monitor ID dynamically
focused_monitor=$(hyprctl monitors -j | jq '.[] | select(.focused == true) | .id')

# 2. Extract the active workspace ID on the OTHER monitor
target_workspace=$(hyprctl monitors -j | jq --argjson id "$focused_monitor" '.[] | select(.id != $id) | .activeWorkspace.id')

# 3. Focus that workspace (moves your cursor/focus to the other monitor)
if [ ! -z "$target_workspace" ]; then
    hyprctl dispatch workspace "$target_workspace"
fi
