#!/bin/bash

STATE_FILE="/tmp/selected_player"

# Функция для определения имени плеера
get_player_display() {
    local player=$1
    if [[ "$player" =~ "chromium" ]]; then
        echo '{"name": "Yandex Music", "icon": ""}'
    elif [[ "$player" =~ "firefox" ]]; then
        echo '{"name": "VK", "icon": ""}'
    elif [[ "$player" =~ "telegram" || "$player" =~ "Telegram" ]]; then
        # Очищаем текстовое имя, чтобы не выводить «Telegramdesktop» на панель
        echo '{"name": "", "icon": ""}'
    elif [ -n "$player" ]; then
        echo "{\"name\": \"${player^}\", \"icon\": \"\"}"
    else
        echo '{"name": "None", "icon": "  "}'
    fi
}

# Читаем текущий выбранный плеер
SELECTED_PLAYER=""
if [ -f "$STATE_FILE" ]; then
    SELECTED_PLAYER=$(cat "$STATE_FILE")
fi

# Проверяем, запущен ли он вообще
if [ -n "$SELECTED_PLAYER" ] && ! playerctl --list-all | grep -q "$SELECTED_PLAYER"; then
    SELECTED_PLAYER=""
fi

if [ -z "$SELECTED_PLAYER" ]; then
    SELECTED_PLAYER=$(playerctl --list-all | head -n 1)
fi

if [ -z "$SELECTED_PLAYER" ]; then
    echo '{"text": ""}'
    exit 0
fi

PLAYER_JSON=$(get_player_display "$SELECTED_PLAYER")
# PLAYER_NAME=$(echo "$PLAYER_JSON" | jq -r '.name')

STATUS=$(playerctl --player="$SELECTED_PLAYER" status 2>/dev/null)
TITLE=$(playerctl --player="$SELECTED_PLAYER" metadata title 2>/dev/null)
ARTIST=$(playerctl --player="$SELECTED_PLAYER" metadata artist 2>/dev/null)

TITLE=$(echo "$TITLE" | xargs)
ARTIST=$(echo "$ARTIST" | xargs)

# 🔐 ЗАЩИТА ПАРСИНГА: Заменяем физический & на безопасный XML-код &amp;
# Теперь Waybar не будет падать, а на панели отобразится красивый знак &
TITLE="${TITLE//&/&amp;}"
ARTIST="${ARTIST//&/&amp;}"

TRACK_INFO=""
if [[ "$STATUS" == "Playing" || "$STATUS" == "Paused" ]]; then
    if [ -n "$TITLE" ] && [ -n "$ARTIST" ]; then
        if [[ "$TITLE" == *"$ARTIST"* ]]; then
            TRACK_INFO=" $TITLE"
        else
            TRACK_INFO=" $ARTIST - $TITLE"
        fi
    elif [ -n "$TITLE" ]; then
        TRACK_INFO=" $TITLE"
    fi
    
    TRACK_INFO=$(echo "$TRACK_INFO" | tr -s ' ' | sed 's/^[[:space:]]*[-–—][[:space:]]*/ /')
    
    if [ -n "$TRACK_INFO" ]; then
        TRACK_INFO=" $TRACK_INFO"
    fi

    if [ ${#TRACK_INFO} -gt 45 ]; then
        TRACK_INFO="${TRACK_INFO:0:42}..."
    fi
fi

# Используем экранированные коды Nerd Fonts, чтобы они точно не превратились в пробелы
STATUS_ICON=""
if [ "$STATUS" == "Playing" ]; then
    STATUS_ICON=$(printf " \uF04B") # Красивый скругленный Play ()
elif [ "$STATUS" == "Paused" ]; then
    STATUS_ICON=$(printf " \uF04C") # Красивый скругленный Pause ()
fi

# Определяем класс для CSS
CSS_CLASS=""
if [[ "$SELECTED_PLAYER" =~ "chromium" ]]; then
    CSS_CLASS="yandex"
elif [[ "$SELECTED_PLAYER" =~ "firefox" ]]; then
    CSS_CLASS="vk"
elif [[ "$SELECTED_PLAYER" =~ "telegram" || "$SELECTED_PLAYER" =~ "Telegram" ]]; then
    CSS_CLASS="telegram"
else
    CSS_CLASS="${STATUS,,}"
fi

# Собираем строку: трек, а затем Nerd-иконка в самом конце
FULL_TEXT=$(echo "$TRACK_INFO$STATUS_ICON" | tr -s ' ')

if [ -z "$FULL_TEXT" ]; then
    FULL_TEXT=" "
fi

echo "{\"text\": \"$FULL_TEXT\", \"class\": \"${CSS_CLASS}\"}"
