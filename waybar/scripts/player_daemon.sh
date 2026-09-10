#!/bin/bash

STATE_FILE="/tmp/selected_player"
RESTORE_FLAG="/tmp/player_daemon_restore_flag"
RESTORED_MARKER="/tmp/player_daemon_restored"

is_yandex_music_player() {
    local player="$1"
    if [[ "$player" == chromium.instance* ]]; then
        local pid="${player#chromium.instance}"
        pid="${pid%%_*}"
        if [[ "$pid" =~ ^[0-9]+$ ]]; then
            if ps -p "$pid" -o args= 2>/dev/null | grep -q "yandex-music"; then
                return 0
            fi
        fi
        return 1
    fi
    return 1
}

is_valid_player() {
    local p="$1"
    if [[ "$p" == chromium.* ]]; then
        is_yandex_music_player "$p"
        return $?
    fi
    return 0
}

is_telegram() {
    [[ "$1" =~ [Tt]elegram ]]
}

get_status() {
    playerctl --player="$1" status 2>/dev/null
}

pause_player() {
    playerctl --player="$1" pause 2>/dev/null
}

play_player() {
    playerctl --player="$1" play 2>/dev/null
}

update_state() {
    if [ -n "$1" ]; then
        echo "$1" > "$STATE_FILE"
    else
        rm -f "$STATE_FILE"
    fi
}

CURRENT_PLAYER=""
PREV_PLAYER=""
RESTORE_PID=""

if [ -f "$STATE_FILE" ]; then
    CANDIDATE=$(cat "$STATE_FILE" | tr -d '[:space:]')
    if [ -n "$CANDIDATE" ] && playerctl --list-all 2>/dev/null | grep -q "$CANDIDATE" && is_valid_player "$CANDIDATE"; then
        CURRENT_PLAYER="$CANDIDATE"
    fi
fi

rm -f "$RESTORE_FLAG" "$RESTORED_MARKER"

schedule_restore() {
    if [ -n "$PREV_PLAYER" ]; then
        touch "$RESTORE_FLAG"
        (
            sleep 0.5
            if [ -f "$RESTORE_FLAG" ]; then
                tg_status=$(get_status "$CURRENT_PLAYER")
                if [ "$tg_status" != "Playing" ]; then
                    play_player "$PREV_PLAYER"
                    echo "$PREV_PLAYER" > "$STATE_FILE"
                    echo "$PREV_PLAYER" > "$RESTORED_MARKER"
                fi
                rm -f "$RESTORE_FLAG"
            fi
        ) &
        RESTORE_PID=$!
    else
        CURRENT_PLAYER=""
        update_state ""
    fi
}

# Фоновый наблюдатель за статусом Telegram
(
    while true; do
        sleep 0.5
        if [ -n "$CURRENT_PLAYER" ] && is_telegram "$CURRENT_PLAYER"; then
            st=$(get_status "$CURRENT_PLAYER")
            if [ "$st" != "Playing" ]; then
                # Telegram не играет, запускаем восстановление
                if [ ! -f "$RESTORE_FLAG" ]; then
                    schedule_restore
                fi
            fi
        fi
    done
) &
WATCHER_PID=$!

while IFS=: read -r player status; do
    # Проверяем маркер восстановления
    if [ -f "$RESTORED_MARKER" ]; then
        restored=$(cat "$RESTORED_MARKER")
        if [ -n "$restored" ]; then
            CURRENT_PLAYER="$restored"
            PREV_PLAYER=""
            rm -f "$RESTORED_MARKER"
        fi
    fi

    [ -z "$player" ] && continue
    player=$(echo "$player" | tr -d '[:space:]')
    status=$(echo "$status" | tr -d '[:space:]')

    if ! is_valid_player "$player"; then
        continue
    fi

    if [ "$status" == "Playing" ]; then
        # Отменяем запланированное восстановление
        if [ -n "$RESTORE_PID" ] && kill -0 "$RESTORE_PID" 2>/dev/null; then
            kill "$RESTORE_PID" 2>/dev/null
            RESTORE_PID=""
        fi
        rm -f "$RESTORE_FLAG"

        if [ "$player" == "$CURRENT_PLAYER" ]; then
            continue
        fi

        if is_telegram "$player"; then
            if [ -n "$CURRENT_PLAYER" ] && ! is_telegram "$CURRENT_PLAYER"; then
                PREV_PLAYER="$CURRENT_PLAYER"
                pause_player "$PREV_PLAYER"
            fi
            CURRENT_PLAYER="$player"
            update_state "$CURRENT_PLAYER"
        else
            if [ -n "$CURRENT_PLAYER" ] && ! is_telegram "$CURRENT_PLAYER"; then
                pause_player "$CURRENT_PLAYER"
                PREV_PLAYER="$CURRENT_PLAYER"
            elif [ -n "$CURRENT_PLAYER" ] && is_telegram "$CURRENT_PLAYER"; then
                pause_player "$CURRENT_PLAYER"
            fi
            CURRENT_PLAYER="$player"
            update_state "$CURRENT_PLAYER"
        fi
    elif [ "$status" == "Paused" ] || [ "$status" == "Stopped" ]; then
        # События Pause/Stop от Telegram можно игнорировать, так как наблюдатель справится
        :
    fi
done < <(playerctl --all-players metadata --format '{{playerName}}:{{status}}' --follow 2>/dev/null)

# Убиваем наблюдателя при завершении
kill $WATCHER_PID 2>/dev/null
