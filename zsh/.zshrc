# === Startup profiling: uncomment the two lines below and run "zsh -i -c exit" to see timings ===
# zmodload zsh/zprof
typeset -a _zshrc_times
_zshrc_tick() { _zshrc_start=$SECONDS; }
_zshrc_tock() { _zshrc_times+=("$1: $((SECONDS - _zshrc_start))s"); }

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="robbyrussell"

# Disable Oh My Zsh automatic updates
zstyle ':omz:update' mode disabled

## Key binds
# Make Ctrl-U (and iTerm Cmd-Delete -> hex 0x15) delete to start of line only
bindkey '^U' backward-kill-line

# Plugins
plugins=(
 git
 zsh-autosuggestions
)

_zshrc_tick && source $ZSH/oh-my-zsh.sh && _zshrc_tock "oh-my-zsh"

# User configuration
export PATH="$HOME/.orbit/bin:$PATH"

# --- pyenv (lazy) ---
function init_pyenv() {
 export PYENV_ROOT="$HOME/.pyenv"
 export PATH="$PYENV_ROOT/bin:$PATH"
 eval "$(pyenv init --path)"
 eval "$(pyenv init -)"
 eval "$(pyenv virtualenv-init -)"
}

# --- nvm (lazy) ---
export NVM_DIR="$HOME/.nvm"
function init_nvm() {
    if [[ -d "$NVM_DIR" ]] ; then
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
    fi
}

# gh completion
if command -v gh >/dev/null 2>&1; then
  _zshrc_tick && eval "$(gh completion -s zsh)" && _zshrc_tock "gh completion"
fi

# iTerm2 shell integration
if [ -f ${HOME}/.iterm2_shell_integration.zsh ]; then
 _zshrc_tick && source "${HOME}/.iterm2_shell_integration.zsh" && _zshrc_tock "iterm2_shell_integration"
fi

# Lazy-load SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
if [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]]; then
  sdk() {
    source "$SDKMAN_DIR/bin/sdkman-init.sh"
    unset -f sdk
    sdk "$@"
  }
fi

# Fuzzy search (fzf)
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# ZSH syntax highlighting
if [ -f /opt/homebrew/bin/brew ]; then
 _zshrc_tick && source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh && _zshrc_tock "zsh-syntax-highlighting"
fi

# zsh-z (jump to frecent dirs)
[ -f $HOME/git/zsh-z/zsh-z.plugin.zsh ] && _zshrc_tick && source $HOME/git/zsh-z/zsh-z.plugin.zsh && _zshrc_tock "zsh-z"

autoload -U compinit; compinit

# === Machine-local / private config (NOT committed) ===
# Put secrets, API tokens, company-internal sourcing, and per-machine PATHs here.
[ -f ~/.zshrc.local ] && source ~/.zshrc.local

# === Profiling summary (section timings) ===
if ((${#_zshrc_times[@]})); then
  echo ""
  echo "zshrc section timings:"
  printf '  %s\n' "${_zshrc_times[@]}"
  echo ""
fi
