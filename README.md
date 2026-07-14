# MacOsAndItermSettings

Personal macOS shell + iTerm2 settings, version-controlled.

> **No secrets in this repo.** Anything sensitive or company-specific (API tokens,
> internal tool sourcing, internal git URL rewrites, work email) lives in
> machine-local files that are gitignored:
> `~/.zshrc.local`, `~/.bashrc.local`, `~/.gitconfig.local`.

## Contents

| Path | Symlinks to |
|------|-------------|
| `zsh/.zshrc` | `~/.zshrc` |
| `zsh/.zprofile` | `~/.zprofile` |
| `zsh/.zshrc_aws_console` | `~/.zshrc_aws_console` |
| `bash/.bashrc` | `~/.bashrc` |
| `bash/.bash_profile` | `~/.bash_profile` |
| `vim/.vimrc` | `~/.vimrc` |
| `git/.gitignore_global` | `~/.gitignore_global` |
| `git/.gitconfig.template` | copy to `~/.gitconfig` (manual) |
| `iterm/com.googlecode.iterm2.plist` | iTerm2 prefs (see below) |

## Install

```bash
cd ~/git/MacOsAndItermSettings
./install.sh
```

This symlinks the dotfiles into `$HOME` (backing up any existing files to `*.bak`).

## Machine-local / private config

Create these by hand on each machine (they are gitignored):

```bash
# ~/.zshrc.local  -- secrets, company-internal sourcing, per-machine PATHs
export CACHE_API_TOKEN="..."            # set your token here (NOT in the repo)
[ -f ~/.sourceprofile/source.sh ]    && source ~/.sourceprofile/source.sh
[ -f ~/.sourceprofile/atlassian.sh ] && source ~/.sourceprofile/atlassian.sh
export PATH="/opt/atlassian/bin:$PATH"
source ~/.zshrc_aws_console           # optional AWS console helper
```

```ini
# ~/.gitconfig.local  -- work email + internal URL rewrites
[user]
	email = you@company.com
[http]
	sslverify = false
[url "ssh://git@internal-host:7997/"]
	insteadOf = https://internal-host/scm/
```

## iTerm2 settings

Two options:

1. **Auto-sync (recommended):** iTerm2 → Settings → General → Preferences →
   check *"Load preferences from a custom folder or URL"* → point it at
   `~/git/MacOsAndItermSettings/iterm/`, and check *"Save changes when iTerm2 quits"*.
   iTerm will then keep the committed plist up to date automatically.

2. **Manual:** the committed `iterm/com.googlecode.iterm2.plist` is a snapshot.
   To restore: `cp iterm/com.googlecode.iterm2.plist ~/Library/Preferences/`
   then `defaults read com.googlecode.iterm2 >/dev/null` (or just relaunch iTerm).

### Notable keybinding included
- **Cmd+Delete** sends hex `0x15` (Ctrl-U), and `.zshrc` binds `^U` to
  `backward-kill-line`, so Cmd+Delete deletes only to the **start** of the line.
