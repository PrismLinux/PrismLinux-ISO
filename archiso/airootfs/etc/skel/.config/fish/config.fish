# Remove the default fish greeting message
set -g fish_greeting

# Disable fish greeting message
function fish_greeting
end

# Format man pages
set -x MANROFFOPT "-c"
set -x MANPAGER "sh -c 'col -bx | bat -l man -p'"

# Prevent history sharing between host and containers
if test "$container" = "podman" -o "$container" = "docker" -o -n "$DISTROBOX_ENTER_PATH"
    set -g fish_history ""
end

# Configure fish color scheme
set -g fish_color_normal normal
set -g fish_color_command blue
set -g fish_color_param cyan
set -g fish_color_error red
set -g fish_color_quote green
set -g fish_color_operator yellow

# Define convenient shell aliases
# Directory Navigation
alias ".."="cd .."
alias "..."="cd ../.."
alias "...."="cd ../../.."
alias "....."="cd ../../../.."
alias "......"="cd ../../../../.."

# Modern Unix Command Replacements
# First check if these packages are installed
if type -q eza
    alias ls="eza -al --color=always --group-directories-first --icons" # preferred listing
    alias l="eza -l --color=always --group-directories-first --icons"   # long format
    alias la="eza -a --color=always --group-directories-first --icons"  # all files and dirs
    alias lt="eza -aT --color=always --group-directories-first --icons" # tree listing
    alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles
    alias tree="eza --tree"
else
    echo "eza not found."
end

if type -q bat
    alias cat="bat"
else
    echo "bat not found."
end

alias untar="tar -xvf"     # Extract tar archives
alias tarnow="tar -acf"    # Create a tar archive
alias grep="grep --color=auto"
alias egrep="egrep --color=auto"
alias fgrep="fgrep --color=auto"
alias wget="wget -c"       # Resume wget by default


# Custom functions are defined in ~/.config/fish/functions/

## Functions for command history
# Functions needed for !! and !$
function __history_previous_command
  switch (commandline -t)
    case "!"
      commandline -t $history[1]; commandline -f repaint
    case "*"
      commandline -i !
  end
end

function __history_previous_command_arguments
    switch (commandline -t)
        case "!"
            commandline -t ""
            commandline -f history-token-search-backward
        case "*"
            commandline -i '$'
    end
end

# Setup key bindings for history
if [ "$fish_key_bindings" = "fish_vi_key_bindings" ]
    bind -Minsert ! __history_previous_command
    bind -Minsert '$' __history_previous_command_arguments
else
    bind ! __history_previous_command
    bind '$' __history_previous_command_arguments
end

# Enhanced history display with timestamps
function history
    builtin history --show-time='%F %T '
end

# Simple backup function
function backup --argument filename
    cp $filename $filename.bak
end

# Improved copy function
function copy
    set count (count $argv | tr -d \n)
    if test "$count" = 2; and test -d "$argv[1]"
        set from (echo $argv[1] | string trim -r -c/)
        set to (echo $argv[2])
        command cp -r $from $to
    else
        command cp $argv
    end
end

# Configure "done" plugin settings (command completion notifications)
# The "done" plugin (in conf.d/done.fish) sends desktop notifications when long-running commands complete
set -g __done_min_cmd_duration 10000       # Show notification after 10 seconds
set -g __done_exclude '^git (?!push|pull|fetch)'  # Don't notify for most git commands except push/pull/fetch
set -g __done_notify_sound 0               # Don't play sound with notifications
set -g __done_notification_duration 3000   # How long notifications stay on screen (ms)
set -U __done_notification_urgency_level low # Set urgency level to low
