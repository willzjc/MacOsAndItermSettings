if [ -f /opt/homebrew/bin/brew ]; then
 eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# pipx
export PATH="$PATH:$HOME/.local/bin"

# JetBrains Toolbox App
if [ -d "$HOME/Library/Application Support/JetBrains/Toolbox/scripts" ]; then
 export PATH="$PATH:$HOME/Library/Application Support/JetBrains/Toolbox/scripts"
fi
