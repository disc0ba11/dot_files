#!/usr/bin/env bash

PIDFILE="/run/user/$UID/work-vpn.pid"
LOGFILE="/run/user/$UID/work-vpn.log"

if [[ -r "$PIDFILE" ]]; then
    read -r pid < "$PIDFILE"

    if [[ "$pid" =~ ^[0-9]+$ ]] \
        && kill -0 "$pid" 2>/dev/null \
        && grep -q "Initialization Sequence Completed" "$LOGFILE" 2>/dev/null
    then
        echo "ТЫ ПОД ВПНОМ БРАТ"
        exit 0
    fi
fi

echo ""
