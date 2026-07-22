set -g fish_greeting ""

# Entorno Omarchy
set -gx OMARCHY_PATH $HOME/.local/share/omarchy
fish_add_path $OMARCHY_PATH/bin $HOME/.local/bin

# Editor
set -gx EDITOR nvim
set -gx SUDO_EDITOR nvim
set -gx BAT_THEME ansi

# Man pages con bat (como en Omarchy)
set -gx MANROFFOPT "-c"
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

# Starship
starship init fish | source

# Zoxide (cd inteligente)
if type -q zoxide
    zoxide init fish | source
    alias cd 'z'
end

# eza (ls mejorado)
if type -q eza
    alias ls 'eza -lh --group-directories-first --icons=auto'
    alias lsa 'eza -lha --group-directories-first --icons=auto'
    alias lt 'eza --tree --level=2 --long --icons --git'
    alias lta 'eza --tree --level=2 --long --icons --git -a'
end

# Utilidades
alias ff 'fzf --preview "bat --style=numbers --color=always {}"'
alias eff '$EDITOR (ff)'

# Vault de Obsidian
alias vault 'cd ~/Vault && claude'

# Utilidades rápidas
function mkcd
    mkdir -p $argv[1] && cd $argv[1]
end

alias syslog 'sudo dmesg --level=err,warn'

# fastfetch al abrir terminal
if test -n "$TERM" -a "$TERM" != "dumb"
    fastfetch
end
