# Colors
WHITE="%F{white}"
TEAL="%F{cyan}"
YELLOW="%F{yellow}"
MAGENTA="%F{magenta}"
RESET="%f"
GREEN="%F{green}"
RED="%F{red}"

# Git info function
function git_info() {
  local branch dirty git_status
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    dirty=$(git status --porcelain 2>/dev/null)
    if [[ -n $dirty ]]; then
      git_status="${RED}✗"
    else
      git_status="${GREEN}✔"
    fi
    echo "${YELLOW}git:(${branch}) ${git_status}${RESET}"
  fi
}

# Left-aligned: user@host, path, git
PROMPT='${MAGENTA}%n@%m${RESET} ${TEAL}%~${RESET} $(git_info)${WHITE}| %D{%Y-%m-%d %H:%M:%S}${RESET}
$ '

# Right-aligned: timestamp
#RPROMPT='${WHITE}%D{%Y-%m-%d %H:%M:%S}${RESET}'

