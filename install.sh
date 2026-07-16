#!/usr/bin/env bash
# Bootstrap + dotfiles installer for ~/git/MacOsAndItermSettings
# Safe to re-run — skips anything already installed/linked.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCEPROFILE_ONLY=0
case "${1:-}" in
  --sourceprofile-only|sourceprofile) SOURCEPROFILE_ONLY=1 ;;
  -h|--help)
    echo "Usage: $0 [--sourceprofile-only]"
    echo "  (default)              bootstrap + link (skips anything already installed)"
    echo "  --sourceprofile-only   only (re)link ~/.sourceprofile — no brew/omz/etc"
    exit 0
    ;;
esac

# ─── helpers ─────────────────────────────────────────────────────────────────

info()    { echo "  [info]  $*"; }
success() { echo "  [ok]    $*"; }
warn()    { echo "  [warn]  $*"; }

link() {
  local src="$REPO_DIR/$1"
  local dest="$HOME/$2"
  if [ ! -e "$src" ]; then warn "skip (source missing): $src"; return; fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    success "already linked: $dest"; return
  fi
  if [ -L "$dest" ] || [ -e "$dest" ]; then
    mv "$dest" "$dest.bak.$(date +%Y%m%d_%H%M%S)"
    info "backed up existing $dest"
  fi
  ln -s "$src" "$dest"
  success "linked $dest -> $src"
}

sp_link() {
  local src="$REPO_DIR/sourceprofile/$1"
  local dest="$HOME/.sourceprofile/$2"
  if [ ! -e "$src" ]; then warn "skip (missing): $src"; return; fi
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    success "already linked: $dest"; return
  fi
  [ -e "$dest" ] && mv "$dest" "$dest.bak.$(date +%Y%m%d_%H%M%S)" && info "backed up $dest"
  ln -s "$src" "$dest"
  success "linked $dest -> $src"
}

link_sourceprofile() {
  local SRCPROFILE="$HOME/.sourceprofile"
  echo
  echo "=== .sourceprofile ==="
  mkdir -p "$SRCPROFILE/scripts" "$SRCPROFILE/services"

  sp_link source.sh       source.sh
  sp_link fzf.sh          fzf.sh
  sp_link osx.sh          osx.sh
  sp_link run-services.sh run-services.sh
  sp_link convertcred.py  convertcred.py
  sp_link dircolors       dircolors

  for f in "$REPO_DIR/sourceprofile/scripts/"*.sh; do
    [ -e "$f" ] || continue
    sp_link "scripts/$(basename "$f")" "scripts/$(basename "$f")"
  done
  for f in "$REPO_DIR/sourceprofile/services/"*.sh; do
    [ -e "$f" ] || continue
    sp_link "services/$(basename "$f")" "services/$(basename "$f")"
  done

  if [ ! -f "$SRCPROFILE/atlassian.sh" ]; then
    warn "~/.sourceprofile/atlassian.sh not found — create it for company-specific config (not managed by this repo)."
  else
    success "~/.sourceprofile/atlassian.sh exists (not managed by this repo)"
  fi
}

if [ "$SOURCEPROFILE_ONLY" -eq 1 ]; then
  link_sourceprofile
  echo
  echo "=== Done (sourceprofile only) ==="
  exit 0
fi

# ─── 0. Prerequisites: git + brew ────────────────────────────────────────────

echo
echo "=== Step 0: Prerequisites ==="

# git — on macOS, running `git` triggers Xcode Command Line Tools install if missing
if command -v git >/dev/null 2>&1; then
  success "git already installed ($(git --version))"
else
  info "git not found — triggering Xcode Command Line Tools install..."
  info "A dialog will appear. Click 'Install' and wait for it to complete, then re-run this script."
  xcode-select --install 2>/dev/null || true
  echo
  warn "Re-run install.sh after Xcode Command Line Tools finishes installing."
  exit 1
fi

# brew
if command -v brew >/dev/null 2>&1; then
  success "Homebrew already installed ($(brew --version | head -1))"
else
  info "Homebrew not found — installing..."
  NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Add brew to PATH for the rest of this script (Apple Silicon path)
  if [ -f /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [ -f /usr/local/bin/brew ]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
  success "Homebrew installed"
fi

# ─── 1. Homebrew packages (Brewfile) ─────────────────────────────────────────

echo
echo "=== Step 1: Homebrew packages ==="
if [ -f "$REPO_DIR/Brewfile" ]; then
  if brew bundle check --file="$REPO_DIR/Brewfile" >/dev/null 2>&1; then
    success "Brewfile already satisfied — skipping brew bundle"
  else
    info "Running brew bundle (only installs missing packages)..."
    brew bundle --file="$REPO_DIR/Brewfile"
    success "brew bundle complete"
  fi
else
  warn "Brewfile not found — skipping"
fi

# ─── 2. oh-my-zsh ────────────────────────────────────────────────────────────

echo
echo "=== Step 2: oh-my-zsh ==="
if [ -d "$HOME/.oh-my-zsh" ]; then
  success "oh-my-zsh already installed"
else
  info "Installing oh-my-zsh (unattended)..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  success "oh-my-zsh installed"
fi

# ─── 3. zsh-autosuggestions plugin ───────────────────────────────────────────

echo
echo "=== Step 3: zsh-autosuggestions ==="
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
AUTOSUGGEST_DIR="$ZSH_CUSTOM/plugins/zsh-autosuggestions"
if [ -d "$AUTOSUGGEST_DIR" ]; then
  success "zsh-autosuggestions already installed"
else
  info "Cloning zsh-autosuggestions..."
  git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "$AUTOSUGGEST_DIR"
  success "zsh-autosuggestions installed"
fi

# ─── 4. zsh-syntax-highlighting ──────────────────────────────────────────────

echo
echo "=== Step 4: zsh-syntax-highlighting ==="
if brew list zsh-syntax-highlighting &>/dev/null 2>&1; then
  success "zsh-syntax-highlighting already installed"
else
  info "Installing zsh-syntax-highlighting via brew..."
  brew install zsh-syntax-highlighting
  success "zsh-syntax-highlighting installed"
fi

# ─── 5. custom zsh theme ─────────────────────────────────────────────────────

echo
echo "=== Step 5: custom zsh theme ==="
THEME_DEST="$ZSH_CUSTOM/themes/customtheme.zsh-theme"
THEME_SRC="$REPO_DIR/zsh/oh-my-zsh-custom/themes/customtheme.zsh-theme"
if [ -L "$THEME_DEST" ] && [ "$(readlink "$THEME_DEST")" = "$THEME_SRC" ]; then
  success "customtheme already linked"
else
  [ -e "$THEME_DEST" ] && mv "$THEME_DEST" "$THEME_DEST.bak.$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$ZSH_CUSTOM/themes"
  ln -s "$THEME_SRC" "$THEME_DEST"
  success "linked customtheme.zsh-theme"
fi

# ─── 6. dotfile symlinks ─────────────────────────────────────────────────────

echo
echo "=== Step 6: dotfile symlinks ==="
link zsh/.zshrc               .zshrc
link zsh/.zprofile            .zprofile
link zsh/.zshrc_aws_console   .zshrc_aws_console
link bash/.bashrc             .bashrc
link bash/.bash_profile       .bash_profile
link vim/.vimrc               .vimrc
link git/.gitignore_global    .gitignore_global

# ─── 7. sourceprofile ────────────────────────────────────────────────────────

link_sourceprofile

# ─── 8. iTerm2 preferences ───────────────────────────────────────────────────

echo
echo "=== Step 8: iTerm2 preferences ==="
ITERM_BUNDLE="com.googlecode.iterm2"
REPO_ITERM_DIR="$REPO_DIR/iterm"

if ! command -v defaults >/dev/null 2>&1; then
  warn "Not on macOS — skipping iTerm2 setup."
else
  # Point iTerm2 at the repo's iterm/ folder as its preference source.
  # This works even while iTerm2 is running; takes effect on next launch.
  defaults write "$ITERM_BUNDLE" PrefsCustomFolder -string "$REPO_ITERM_DIR"
  defaults write "$ITERM_BUNDLE" LoadPrefsFromCustomFolder -bool true
  defaults write "$ITERM_BUNDLE" NoSyncNeverRemindPrefsChangesLostForFile -bool true
  defaults write "$ITERM_BUNDLE" NoSyncNeverRemindPrefsChangesLostForFile_selection -int 0
  success "iTerm2 will load preferences from: $REPO_ITERM_DIR"
  info "Relaunch iTerm2 for settings to take effect."
  info "Future iTerm2 changes will auto-save back to the repo on quit."
fi

# ─── Done ────────────────────────────────────────────────────────────────────

echo
echo "=== Done! ==="
echo
if [ ! -f "$HOME/.zshrc.local" ]; then
  warn "~/.zshrc.local not found — create it for secrets/company-specific config."
  echo "  See README.md for the template."
else
  success "~/.zshrc.local exists"
fi
if [ ! -f "$HOME/.gitconfig" ]; then
  warn "~/.gitconfig not found — copy git/.gitconfig.template to ~/.gitconfig and fill in your details."
else
  success "~/.gitconfig exists"
fi
echo
echo "  Next steps:"
echo "    1. Relaunch iTerm2 to load your saved settings"
echo "    2. Reload your shell:  source ~/.zshrc  (or open a new tab)"
echo "    3. If ~/.zshrc.local is missing, create it — see README.md"
echo "  Fast re-link later:  $0 --sourceprofile-only"
