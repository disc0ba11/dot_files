#!/usr/bin/env bash

source "$HOME/.env"

if [[ -z "$WORK_VPN_PATH" ]]; then
    echo "WORK_VPN_PATH не задан" >&2
    exit 1
fi

if [[ ! -f "$WORK_VPN_PATH" ]]; then
    echo "VPN-конфиг не найден: $WORK_VPN_PATH" >&2
    exit 1
fi

PIDFILE="/run/user/$UID/work-vpn.pid"
LOGFILE="/run/user/$UID/work-vpn.log"

vpn_running() {
    [[ -f "$PIDFILE" ]] || return 1

    local pid
    read -r pid < "$PIDFILE"

    [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

if vpn_running; then
    echo "выключаю VPN..."

    kill "$(cat "$PIDFILE")"

    # Даём OpenVPN немного времени корректно выполнить down-скрипты.
    for _ in {1..20}; do
        vpn_running || break
        sleep 0.1
    done

    rm -f "$PIDFILE" "$LOGFILE"
    pkill -RTMIN+9 waybar

    echo "VPN выключен"
    exit 0
fi

# Убираем мусор от предыдущего запуска.
rm -f "$PIDFILE" "$LOGFILE"

echo "включаю VPN..."

env -u NOTIFY_SOCKET openvpn \
    --config "$WORK_VPN_PATH" \
    --daemon work-vpn \
    --writepid "$PIDFILE" \
    --log "$LOGFILE"

# Ждём настоящей успешной инициализации.
for _ in {1..200}; do
    if grep -q "Initialization Sequence Completed" "$LOGFILE" 2>/dev/null; then
        echo "VPN включен"
        pkill -RTMIN+9 waybar
        exit 0
    fi

    # Если процесс уже умер — ждать больше нечего.
    if [[ -f "$PIDFILE" ]]; then
        read -r pid < "$PIDFILE"

        if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
            break
        fi
    fi

    sleep 0.1
done

echo "не удалось включить VPN"

if [[ -f "$LOGFILE" ]]; then
    echo
    tail -n 15 "$LOGFILE"
fi

# Если процесс почему-то жив, но за 20 секунд так и не инициализировался —
# не оставляем полуподнятый VPN.
if vpn_running; then
    kill "$(cat "$PIDFILE")" 2>/dev/null
fi

rm -f "$PIDFILE"
pkill -RTMIN+9 waybar

exit 1
