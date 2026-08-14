# ~/.config/zsh/.zshrc — HWE interactive zsh config.

# --- History (kept in XDG state, not in the repo) -------------------------
HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/zsh/history"
HISTSIZE=50000
SAVEHIST=50000
mkdir -p "${HISTFILE:h}"
setopt inc_append_history share_history hist_ignore_all_dups hist_reduce_blanks hist_verify

# --- Sane shell behaviour --------------------------------------------------
setopt auto_cd interactive_comments globdots   # <--- добавлено globdots для скрытых файлов
bindkey -e                                   # emacs keybinds (Ctrl-A/E/R…)

# Up/Down: prefix history search — type `g`, press ↑ to cycle only `g…` lines.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
[[ -n ${terminfo[kcuu1]} ]] && bindkey "${terminfo[kcuu1]}" up-line-or-beginning-search
[[ -n ${terminfo[kcdn1]} ]] && bindkey "${terminfo[kcdn1]}" down-line-or-beginning-search
bindkey '^[[A' up-line-or-beginning-search                  # ↑ (normal mode)
bindkey '^[[B' down-line-or-beginning-search                # ↓ (normal mode)
bindkey '^[OA' up-line-or-beginning-search                  # ↑ (application mode)
bindkey '^[OB' down-line-or-beginning-search                # ↓ (application mode)

# Word motion: zsh's emacs keymap only binds Alt+b/f, so Ctrl+←/→ arrive unbound
[[ -n ${terminfo[kLFT5]} ]] && bindkey "${terminfo[kLFT5]}" backward-word   # Ctrl+←
[[ -n ${terminfo[kRIT5]} ]] && bindkey "${terminfo[kRIT5]}" forward-word    # Ctrl+→
[[ -n ${terminfo[kLFT3]} ]] && bindkey "${terminfo[kLFT3]}" backward-word   # Alt+←
[[ -n ${terminfo[kRIT3]} ]] && bindkey "${terminfo[kRIT3]}" forward-word    # Alt+→
[[ -n ${terminfo[kDC5]}  ]] && bindkey "${terminfo[kDC5]}"  kill-word       # Ctrl+Del
bindkey '^[[1;5D' backward-word                             # fallbacks (no terminfo)
bindkey '^[[1;5C' forward-word
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[3;5~' kill-word
bindkey '^H'      backward-kill-word                        # Ctrl+Backspace

bindkey "^[[H" beginning-of-line
bindkey "^[[F" end-of-line
bindkey '^?' backward-delete-char
bindkey "^[[3~" delete-char

# --- Completion System & fzf-tab Configuration -----------------------------

# Сброс старых стилей во избежание конфликтов
zstyle -d ':completion:*'
zstyle -d ':fzf-tab:*'

# Инициализация compinit с использованием правильного XDG-кэша
autoload -Uz compinit
_zdump="${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"
mkdir -p "${_zdump:h}"
compinit -d "$_zdump"
unset _zdump

# Ключевое исправление: используем только _complete для стандартного поведения.
# Убираем _match и _ignored, чтобы при неоднозначности сразу открывалось меню.
zstyle ':completion:*' completer _complete

# Включаем menu select с нулевым порогом (активация fzf-tab с 1-го нажатия Tab)
zstyle ':completion:*' menu select=0
zstyle ':completion:*' insert-unambiguous false

# Регистронезависимость + кириллица + честный подстрочный поиск (*слово*)
zstyle ':completion:*' matcher-list 'm:{a-zA-Zа-яА-Я}={A-Za-zА-Яа-я}' 'l:|=* r:|=*'

# Цвета и оформление
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*:descriptions' format '[%d]'

setopt complete_in_word
setopt ALWAYS_TO_END

# Подключение fzf-tab (Используем $HOME вместо тильды)
if [[ -f "$HOME/Downloads/fzf-tab/fzf-tab.plugin.zsh" ]]; then
    source "$HOME/Downloads/fzf-tab/fzf-tab.plugin.zsh"
else
    echo "⚠️ ПЛАГИН НЕ НАЙДЕН ПО ЭТОМУ ПУТИ!"
fi

# Настройки интерфейса fzf-tab
zstyle ':fzf-tab:*' fzf-command fzf
zstyle ':fzf-tab:*' fzf-preview '~/.config/zsh/fzf-preview $realpath'
zstyle ':fzf-tab:*' fzf-flags --height=70% --border

compdef _files cat
compdef _files bat

# Стиль перемещения по словам
autoload -U select-word-style
select-word-style bash

# --- Modern CLI aliases ----------------------------------------------------
if command -v eza >/dev/null; then
    alias ls='eza --icons=auto --group-directories-first'
    alias ll='eza -lah --icons=auto --group-directories-first'
    alias tree='eza --tree --icons=auto'
fi

if command -v bat >/dev/null; then
    alias cat='bat --plain --paging=never'
elif command -v batcat >/dev/null; then
    alias cat='batcat --plain --paging=never'
fi
command -v fd >/dev/null || { command -v fdfind >/dev/null && alias fd='fdfind'; }
alias grep='grep --color=auto'
alias ..='cd ..'
alias ...='cd ../..'
alias ssh="env TERM=xterm-256color ssh"

# --- Plugins (Исправлен порядок загрузки!) ----------------------------------
# ВАЖНО: zsh-syntax-highlighting обязан идти СТРОГО ДО zsh-autosuggestions.
# Только в таком порядке они не ломают фоновое (теневое) дополнение.
_p=/usr/share/zsh/plugins

if [[ -r $_p/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
    source $_p/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [[ -r $_p/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source $_p/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

unset _p

# --- Integrations ----------------------------------------------------------
command -v zoxide >/dev/null && eval "$(zoxide init zsh)"

# --- Prompt: starship, single line (config: ~/.config/starship.toml) -------
command -v starship >/dev/null && eval "$(starship init zsh)"

source ~/.env
PATH="$PATH:/home/$USER/.local/bin/"
