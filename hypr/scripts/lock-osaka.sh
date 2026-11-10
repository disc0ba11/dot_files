#!/usr/bin/env bash

video_pids=()

stop_videos() {
    for pid in "${video_pids[@]}"; do
        kill "$pid" 2>/dev/null || true
    done
}
trap stop_videos EXIT

play_on() {
    mpvpaper -l overlay -o 'no-audio loop-file=inf' "$1" "$2" &
    video_pids+=("$!")
}

play_on HDMI-A-1 "$HOME/Videos/osaka-microwave.mp4"
play_on eDP-1    "$HOME/Videos/osaka-microwave.mp4"

hyprlock "$@"
