#!/usr/bin/env bash
set -euo pipefail

# Run as your desktop user, from a terminal inside Hyprland.
if (( EUID == 0 )); then
    printf '%s\n' 'Запусти установщик от своего пользователя, без sudo.' >&2
    exit 1
fi
for cmd in python3 pactl hyprctl systemctl; do
    if ! command -v "$cmd" >/dev/null; then
        printf 'Не найдена команда: %s\nВ Arch для Python и pactl: sudo pacman -S --needed python libpulse\n' "$cmd" >&2
        exit 1
    fi
done
: "${HYPRLAND_INSTANCE_SIGNATURE:?Запусти установщик из терминала внутри Hyprland}"
: "${XDG_RUNTIME_DIR:?Не задан XDG_RUNTIME_DIR}"
case "$(hyprctl locked)" in
    true|false) ;;
    *) printf '%s\n' 'Эта версия Hyprland не поддерживает hyprctl locked.' >&2; exit 1 ;;
esac
pactl info >/dev/null

task_lib="${XDG_DATA_HOME:-$HOME/.local/share}/hyprlock-audio"
task_bin="$HOME/.local/bin"
task_units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
mkdir -p "$task_lib" "$task_bin" "$task_units"
task_stamp="$(date +%Y%m%d-%H%M%S)-$$"
for path in "$task_lib/daemon.py" "$task_bin/start-hyprlock-audio" "$task_units/hyprlock-audio.service"; do
    if [[ -e "$path" ]]; then
        cp -a -- "$path" "$path.backup-$task_stamp"
    fi
done

cat > "$task_lib/daemon.py" <<'PYTHON'
#!/usr/bin/env python3
"""Mute audio while Hyprland is locked; preserve per-device mute flags."""
import fcntl
import hashlib
import json
import logging
import os
from pathlib import Path
import signal
import subprocess
import threading

LOG = logging.getLogger("hyprlock-audio")
KINDS = {"sink": "sinks", "source": "sources"}
STOP = threading.Event()


def command(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=2,
                            env={**os.environ, "LC_ALL": "C"})
    if result.returncode:
        raise RuntimeError(f"{args[0]}: {result.stderr.strip() or result.stdout.strip()}")
    return result.stdout.strip()


def locked():
    value = command("hyprctl", "locked")
    if value not in ("true", "false"):
        raise RuntimeError(f"Unknown lock state: {value!r}")
    return value == "true"


def devices(kind):
    result = {}
    for item in json.loads(command("pactl", "--format=json", "list", KINDS[kind])):
        # Monitor sources capture playback rather than microphones.
        if kind == "source" and item.get("monitor_of_sink") not in (None, -1, 4294967295, "n/a"):
            continue
        if not isinstance(item.get("mute"), bool):
            raise RuntimeError("Unexpected pactl mute format")
        result[item["name"]] = item["mute"]
    return result


def set_mute(kind, name, muted):
    command("pactl", f"set-{kind}-mute", name, "1" if muted else "0")


class AudioState:
    def __init__(self, path):
        self.path = path
        self.saved = {kind: {} for kind in KINDS}
        self.errors = {}
        if path.exists():
            value = json.loads(path.read_text())
            if (not isinstance(value, dict) or set(value) != set(KINDS)
                    or any(not isinstance(v, dict) for v in value.values())
                    or any(not isinstance(n, str) or not isinstance(m, bool)
                           for v in value.values() for n, m in v.items())):
                raise RuntimeError("Invalid saved audio state; refusing to overwrite it")
            self.saved = value

    def save(self):
        # Write original values BEFORE muting. Keep them across service restarts.
        temporary = self.path.with_suffix(".tmp")
        temporary.write_text(json.dumps(self.saved))
        temporary.chmod(0o600)
        temporary.replace(self.path)

    def step(self, is_locked):
        for kind in KINDS:
            try:
                if not is_locked and not self.saved[kind]:
                    continue
                current = devices(kind)
                if is_locked:
                    added = {name: mute for name, mute in current.items()
                             if name not in self.saved[kind]}
                    if added:
                        self.saved[kind].update(added)
                        self.save()
                        LOG.info("Saved %s mute states: %s", kind, added)
                    for name, mute in current.items():
                        if not mute:
                            set_mute(kind, name, True)
                else:
                    # Restore by symbolic name, never by a recycled numeric ID.
                    # Disconnected devices stay pending until they reappear.
                    for name, mute in list(self.saved[kind].items()):
                        if name not in current:
                            continue
                        if current[name] != mute:
                            set_mute(kind, name, mute)
                        del self.saved[kind][name]
                        self.save()
                        LOG.info("Restored %s %s: muted=%s", kind, name, mute)
                self.errors.pop(kind, None)
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
                # A failure on speakers must not prevent muting the microphone.
                message = str(exc)
                if self.errors.get(kind) != message:
                    LOG.warning("%s: %s; will retry", kind, message)
                    self.errors[kind] = message


def main():
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    os.umask(0o077)
    signature = os.environ["HYPRLAND_INSTANCE_SIGNATURE"]
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    compositor = runtime / "hypr" / signature / ".socket.sock"
    state_dir = runtime / "hyprlock-audio"
    state_dir.mkdir(mode=0o700, exist_ok=True)
    identity = hashlib.sha256(signature.encode()).hexdigest()[:24]
    with (state_dir / f"{identity}.lock").open("w") as guard:
        fcntl.flock(guard, fcntl.LOCK_EX | fcntl.LOCK_NB)
        state = AudioState(state_dir / f"{identity}.json")
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, lambda *_: STOP.set())
        previous = None
        error = None
        LOG.info("Watching Hyprland lock state every 0.5 seconds")
        while not STOP.is_set():
            if not compositor.exists():
                LOG.info("Hyprland instance ended; saved state retained")
                return
            try:
                is_locked = locked()
                if is_locked != previous:
                    LOG.info("Session %s", "locked" if is_locked else "unlocked")
                    previous = is_locked
                state.step(is_locked)
                error = None
            except (RuntimeError, subprocess.TimeoutExpired) as exc:
                # Unknown lock status is NEVER treated as an unlock.
                if str(exc) != error:
                    LOG.warning("Cannot read lock state: %s; will retry", exc)
                    error = str(exc)
            STOP.wait(0.5)
        # Do not unmute on service stop: the session may still be locked.
        LOG.info("Stopped; original mute states retained for next start")


if __name__ == "__main__":
    main()
PYTHON

# systemd specifiers must be escaped in paths embedded in unit files.
task_python="$task_lib/daemon.py"
task_python="${task_python//%/%%}"
task_python="${task_python//\\/\\\\}"
task_python="${task_python//\"/\\\"}"
cat > "$task_units/hyprlock-audio.service" <<EOF
[Unit]
Description=Preserve audio mute state across Hyprland screen locks
PartOf=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 "$task_python"
Restart=on-failure
RestartSec=2
TimeoutStopSec=10
UMask=0077
NoNewPrivileges=yes
EOF

cat > "$task_bin/start-hyprlock-audio" <<'LAUNCHER'
#!/usr/bin/env bash
set -euo pipefail
: "${HYPRLAND_INSTANCE_SIGNATURE:?Run inside Hyprland}"
systemctl --user import-environment HYPRLAND_INSTANCE_SIGNATURE
systemctl --user restart hyprlock-audio.service
LAUNCHER
chmod 700 "$task_bin/start-hyprlock-audio"
python3 -m py_compile "$task_lib/daemon.py"
systemctl --user daemon-reload
"$task_bin/start-hyprlock-audio"
systemctl --user --no-pager status hyprlock-audio.service
printf '\n%s\n' \
    'Установлено. Добавь в автозапуск Hyprland:' \
    'exec-once = ~/.local/bin/start-hyprlock-audio' \
    '' \
    'Бинд блокировки оставь обычным: bind = $mainMod, L, exec, hyprlock' \
    'Логи: journalctl --user -u hyprlock-audio.service -f' \
    'Остановка: systemctl --user stop hyprlock-audio.service'
