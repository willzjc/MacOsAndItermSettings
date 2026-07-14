# Misc aliases
alias cdg='cd ~/git'
alias cds='cd ~/sandbox'
alias cdw='cd ~/workspace'
alias wget="wget --no-check-certificate"
alias mergemaster="git fetch origin master:master && git merge master"

# quickly creates a new folder with today's date
function cdtd {
	DATESTR=$(date +%Y%m%d)
	mkdir -p $HOME/text/$DATESTR
	cd $HOME/text/$DATESTR
	ln -sfn $HOME/text/$DATESTR ~/text/today
}

function td {
 DATESTR=$(date +%Y%m%d)
 if [ ! -d "$HOME/text/$DATESTR" ] ; then
  PREV_LINK=$(readlink -f ~/text/today)
  mkdir -p $HOME/text/$DATESTR
  if [ ! -z $PREV_LINK ] ; then
   ln -sfn $PREV_LINK $HOME/text/$DATESTR/previous
   ln -sfn $PREV_LINK $HOME/text/previous
  fi
 fi

 if [ ! -d "$HOME/text/logs" ] ; then
  mkdir -p $HOME/text/logs
 fi

 if [ ! -f $HOME/text/logs/cmd_history.$DATESTR.log ] ; then
  history > $HOME/text/logs/cmd_history.$DATESTR.log
  cp $HOME/.zsh_history $HOME/text/logs/zsh_history.$DATESTR.log
 fi

 ln -sfn $HOME/text/$DATESTR $HOME/text/today
 ln -sfn $HOME/text/$DATESTR $HOME/text/current

 cd $HOME/text/today
}

for extrasource in '~/.sourceprofile/aws.sh'; do
{
 if [ -f $extrasource ] ; then
 {
  source "$extrasource"
 }
 fi
}
done

if [ $(uname -s) = "Darwin" ] ; then
{
 source ~/.sourceprofile/osx.sh
}
fi

gittree() {
  local changed_files=$(git diff-tree --no-commit-id --name-only -r HEAD)
  if [ -z "$changed_files" ]; then
    echo "No files were changed in the latest commit."
    return 0
  fi
  if command -v tree &> /dev/null; then
    local temp_file=$(mktemp)
    echo "$changed_files" > "$temp_file"
    echo "Files changed in the latest commit:"
    tree --fromfile "$temp_file"
    rm "$temp_file"
  else
    echo "Files changed in the latest commit:"
    echo "$changed_files" | sort | sed 's/^/├── /'
    echo "└── (Install 'tree' command for better visualization)"
  fi
}

gzip_large_files() {
  local gzipped_files=()
  while IFS= read -r -d '' file; do
    if [[ $(stat -f%z "$file") -gt $((1 * 1024 * 1024)) ]]; then
      gzip "$file"
      gzipped_files+=("${file}.gz")
    fi
  done < <(find . -type f ! -name "*.gz" ! -lname "*" -print0)
  echo "Gzipped files:"
  for f in "${gzipped_files[@]}"; do
    echo "$f"
  done
}

showservices() {
  local services_dir="${HOME}/.sourceprofile/services"
  local pid_dir="${TMPDIR:-/tmp}/wzjc-services"
  local service name pidfile pid svc_status
  if [ ! -d "$services_dir" ]; then
    echo "No services directory: $services_dir"
    return 1
  fi
  printf '%-32s %s\n' "SERVICE" "STATUS"
  for service in "$services_dir"/*; do
    [ -e "$service" ] || continue
    [ -f "$service" ] || continue
    name=$(basename "$service")
    pidfile="${pid_dir}/${name}.pid"
    svc_status="stopped"
    if [ ! -x "$service" ]; then
      svc_status="disabled (not executable)"
    elif [ -f "$pidfile" ]; then
      pid=$(cat "$pidfile" 2>/dev/null)
      if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        svc_status="running (pid $pid)"
      fi
    fi
    printf '%-32s %s\n' "$name" "$svc_status"
  done
}

# Load scripts from ~/.sourceprofile/scripts/
if [ -d ~/.sourceprofile/scripts/ ]; then
  for script in $(find ~/.sourceprofile/scripts/ -maxdepth 1 -name "*.sh" -type f 2>/dev/null); do
    if [ -f "$script" ]; then
      source "$script"
    fi
  done
fi

# Start wzjc services on interactive shell startup
if [ -t 0 ] && [ -f ~/.sourceprofile/run-services.sh ]; then
  . ~/.sourceprofile/run-services.sh
fi
# GIT_TOKEN removed — set this in ~/.zshrc.local
# export GIT_TOKEN=your_token_here
