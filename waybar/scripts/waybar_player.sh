#!/bin/bash

STATE_FILE="/tmp/selected_player"

# Проверка, является ли chromium-плеер Яндекс Музыкой
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

# Проверка, допустим ли плеер (не Pachca и т.п.)
is_valid_player() {
    local p="$1"
    if [[ "$p" == chromium.* ]]; then
        is_yandex_music_player "$p"
        return $?
    fi
    return 0
}

# Функция для определения имени плеера
get_player_display() {
    local player=$1
    if [[ "$player" =~ "chromium" ]]; then
        echo '{"name": "Yandex Music", "icon": ""}'
    elif [[ "$player" =~ "firefox" ]]; then
        echo '{"name": "VK", "icon": ""}'
    elif [[ "$player" =~ "telegram" || "$player" =~ "Telegram" ]]; then
        echo '{"name": "Telegram", "icon": ""}'
    elif [ -n "$player" ]; then
        echo "{\"name\": \"${player^}\", \"icon\": \"\"}"
    else
        echo '{"name": "None", "icon": "  "}'
    fi
}

# Проверка наличия реальных метаданных с учётом ошибок playerctl
has_metadata() {
    local player=$1
    local title artist album xesam_title xesam_artist xesam_album
    local rc_title rc_artist rc_album rc_xesam_title rc_xesam_artist rc_xesam_album

    title=$(playerctl --player="$player" metadata title 2>&1); rc_title=$?
    artist=$(playerctl --player="$player" metadata artist 2>&1); rc_artist=$?
    album=$(playerctl --player="$player" metadata album 2>&1); rc_album=$?
    xesam_title=$(playerctl --player="$player" metadata xesam:title 2>&1); rc_xesam_title=$?
    xesam_artist=$(playerctl --player="$player" metadata xesam:artist 2>&1); rc_xesam_artist=$?
    xesam_album=$(playerctl --player="$player" metadata xesam:album 2>&1); rc_xesam_album=$?

    check_field() {
        local output="$1"
        local rc=$2
        [ $rc -ne 0 ] && return 1
        output_clean=$(echo "$output" | tr -d '[:space:]')
        [ -z "$output_clean" ] && return 1
        [[ "$output_clean" == *"Noplayersfound"* ]] && return 1
        [[ "$output_clean" == *"Noplayercouldhandlethiscommand"* ]] && return 1
        return 0
    }

    if check_field "$title" $rc_title || \
       check_field "$artist" $rc_artist || \
       check_field "$album" $rc_album || \
       check_field "$xesam_title" $rc_xesam_title || \
       check_field "$xesam_artist" $rc_xesam_artist || \
       check_field "$xesam_album" $rc_xesam_album; then
        return 0
    else
        return 1
    fi
}

# Вывод информации о плеере в формате Waybar
print_player_info() {
    local player=$1
    local status=$(playerctl --player="$player" status 2>/dev/null)
    local title=$(playerctl --player="$player" metadata title 2>/dev/null)
    local artist=$(playerctl --player="$player" metadata artist 2>/dev/null)

    # Очищаем поля от сообщений об ошибках
    if [[ "$title" == *"No players found"* || "$title" == *"No player could handle this command"* ]]; then
        title=""
    fi
    if [[ "$artist" == *"No players found"* || "$artist" == *"No player could handle this command"* ]]; then
        artist=""
    fi

    title=$(echo "$title" | xargs)
    artist=$(echo "$artist" | xargs)

    # Защита парсинга
    title="${title//&/&amp;}"
    artist="${artist//&/&amp;}"

    local track_info=""
    if [[ "$status" == "Playing" || "$status" == "Paused" ]]; then
        if [ -n "$title" ] && [ -n "$artist" ]; then
            if [[ "$title" == *"$artist"* ]]; then
                track_info=" $title"
            else
                track_info=" $artist - $title"
            fi
        elif [ -n "$title" ]; then
            track_info=" $title"
        fi

        track_info=$(echo "$track_info" | tr -s ' ' | sed 's/^[[:space:]]*[-–—][[:space:]]*/ /')

        if [ -n "$track_info" ]; then
            track_info=" $track_info"
        fi

        if [ ${#track_info} -gt 45 ]; then
            track_info="${track_info:0:42}..."
        fi
    fi

    # Иконки статуса
    local status_icon=""
    if [ "$status" == "Playing" ]; then
        status_icon=$(printf " \uF04B")
    elif [ "$status" == "Paused" ]; then
        status_icon=$(printf " \uF04C")
    fi

    # Классы CSS
    local css_class=""
    if [[ "$player" =~ "chromium" ]]; then
        css_class="yandex"
    elif [[ "$player" =~ "firefox" ]]; then
        css_class="vk"
    elif [[ "$player" =~ "telegram" || "$player" =~ "Telegram" ]]; then
        css_class="telegram"
    else
        css_class="${status,,}"
    fi

    local full_text=$(echo "$track_info$status_icon" | tr -s ' ')
    [ -z "$full_text" ] && full_text=" "

    echo "{\"text\": \"$full_text\", \"class\": \"${css_class}\"}"
}

# --- Логика переключения (режим "next") ---
if [ "$1" == "next" ]; then
    # Получаем список всех валидных плееров
    ALL_PLAYERS=()
    while IFS= read -r p; do
        if is_valid_player "$p"; then
            ALL_PLAYERS+=("$p")
        fi
    done < <(playerctl --list-all 2>/dev/null)

    if [ ${#ALL_PLAYERS[@]} -eq 0 ]; then
        rm -f "$STATE_FILE"
        exit 0
    fi

    # Читаем текущего плеера
    CURRENT=""
    if [ -f "$STATE_FILE" ]; then
        CURRENT=$(cat "$STATE_FILE" | tr -d '[:space:]')
    fi

    # Находим индекс текущего в списке
    CURRENT_INDEX=-1
    if [ -n "$CURRENT" ]; then
        for i in "${!ALL_PLAYERS[@]}"; do
            if [ "${ALL_PLAYERS[$i]}" == "$CURRENT" ]; then
                CURRENT_INDEX=$i
                break
            fi
        done
    fi

    # Перебираем, начиная со следующего, пока не найдём с метаданными
    FOUND=""
    START_INDEX=$(( (CURRENT_INDEX + 1) % ${#ALL_PLAYERS[@]} ))
    for (( j=0; j<${#ALL_PLAYERS[@]}; j++ )); do
        idx=$(( (START_INDEX + j) % ${#ALL_PLAYERS[@]} ))
        candidate="${ALL_PLAYERS[$idx]}"
        if has_metadata "$candidate"; then
            FOUND="$candidate"
            break
        fi
    done

    if [ -n "$FOUND" ]; then
        echo "$FOUND" > "$STATE_FILE"
        print_player_info "$FOUND"
    else
        rm -f "$STATE_FILE"
        echo '{"text": ""}'
    fi
    exit 0
fi

# --- Режим отображения (без аргументов) ---
SELECTED_PLAYER=""
if [ -f "$STATE_FILE" ]; then
    SELECTED_PLAYER=$(cat "$STATE_FILE" | tr -d '[:space:]')
fi

# Проверяем, что сохранённый плеер ещё существует и валиден
if [ -n "$SELECTED_PLAYER" ]; then
    if ! playerctl --list-all 2>/dev/null | grep -q "$SELECTED_PLAYER" || ! is_valid_player "$SELECTED_PLAYER" || ! has_metadata "$SELECTED_PLAYER"; then
        SELECTED_PLAYER=""
    fi
fi

# Если нет валидного сохранённого плеера, ищем первый с метаданными
if [ -z "$SELECTED_PLAYER" ]; then
    while IFS= read -r p; do
        if is_valid_player "$p" && has_metadata "$p"; then
            SELECTED_PLAYER="$p"
            break
        fi
    done < <(playerctl --list-all 2>/dev/null)
fi

if [ -z "$SELECTED_PLAYER" ]; then
    rm -f "$STATE_FILE"
    echo '{"text": ""}'
    exit 0
fi

echo "$SELECTED_PLAYER" > "$STATE_FILE"
print_player_info "$SELECTED_PLAYER"
