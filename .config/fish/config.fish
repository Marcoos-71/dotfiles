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
    # tree con iconos, colores y git
    # uso: tree [ruta] [-L nivel]  (nivel por defecto: 3)
    function tree
        set args
        set level 3
        set i 1
        while test $i -le (count $argv)
            if test $argv[$i] = "-L" -o $argv[$i] = "--level"
                set i (math $i + 1)
                set level $argv[$i]
            else
                set args $args $argv[$i]
            end
            set i (math $i + 1)
        end
        eza --tree --level=$level --icons --git --group-directories-first $args
    end
end

# LS_COLORS con vivid (Catppuccin Mocha) — activo solo si vivid está instalado
if type -q vivid
    set -gx LS_COLORS (vivid generate catppuccin-mocha)
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
