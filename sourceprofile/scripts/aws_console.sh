aws_console_url() {
  emulate -L zsh
  setopt localoptions pipefail

  local do_open=0
  local debug=0
  local region="${AWS_REGION:-us-east-1}"
  local dest=""

  while (( $# )); do
    case "$1" in
      -o|--open) do_open=1 ;;
      -d|--debug) debug=1 ;;
      --dest) shift; dest="${1:-}" ;;
      --region) shift; region="${1:-}" ;;
      -h|--help)
        cat <<'EOF'
aws_console_url [--open|-o] [--dest <url>] [--region <region>] [--debug|-d]

Requires env vars:
  AWS_ACCESS_KEY_ID
  AWS_SECRET_ACCESS_KEY
  AWS_SESSION_TOKEN (or AWS_SECURITY_TOKEN)

Prints a federated AWS Console login URL. Treat the URL like a password.
EOF
        return 0
        ;;
      *)
        dest="$1"
        ;;
    esac
    shift
  done

  local ak="${AWS_ACCESS_KEY_ID-}"
  local sk="${AWS_SECRET_ACCESS_KEY-}"
  local st="${AWS_SESSION_TOKEN-${AWS_SECURITY_TOKEN-}}"

  if [[ -z "$ak" || -z "$sk" || -z "$st" ]]; then
    print -u2 -- "aws_console_url: missing required env vars."
    print -u2 -- "Need: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_SESSION_TOKEN (or AWS_SECURITY_TOKEN)."
    return 1
  fi

  if [[ -z "$dest" ]]; then
    dest="https://${region}.console.aws.amazon.com/console/home?region=${region}"
  fi

  command -v curl >/dev/null 2>&1 || { print -u2 -- "aws_console_url: curl not found"; return 1; }
  command -v python3 >/dev/null 2>&1 || { print -u2 -- "aws_console_url: python3 not found"; return 1; }

  # Build session JSON (unencoded; let curl --data-urlencode do the encoding)
  local session_json
  session_json="$(
    python3 - <<'PY'
import os, json
session = {
  "sessionId": os.environ["AWS_ACCESS_KEY_ID"],
  "sessionKey": os.environ["AWS_SECRET_ACCESS_KEY"],
  "sessionToken": os.environ.get("AWS_SESSION_TOKEN") or os.environ.get("AWS_SECURITY_TOKEN") or ""
}
print(json.dumps(session, separators=(",",":")))
PY
  )" || return 1

  (( debug )) && {
    print -u2 -- "aws_console_url debug: region=${region}"
    print -u2 -- "aws_console_url debug: dest=${dest}"
    print -u2 -- "aws_console_url debug: using AWS_SESSION_TOKEN? $([[ -n ${AWS_SESSION_TOKEN-} ]] && echo yes || echo no)"
  }

  # Fetch SigninToken (fail on HTTP errors, show errors)
  local token_resp
  if (( debug )); then
    token_resp="$(
      curl -fSsv --get "https://signin.aws.amazon.com/federation" \
        --data-urlencode "Action=getSigninToken" \
        --data-urlencode "Session=${session_json}" 2>&1
    )" || {
      print -u2 -- "aws_console_url: curl failed while requesting SigninToken (see debug output above)."
      return 1
    }
    # In debug mode, curl output includes headers/body mixed; re-run cleanly for parsing:
    token_resp="$(
      curl -fsS --get "https://signin.aws.amazon.com/federation" \
        --data-urlencode "Action=getSigninToken" \
        --data-urlencode "Session=${session_json}"
    )" || {
      print -u2 -- "aws_console_url: failed to get SigninToken (HTTP/network error)."
      return 1
    }
  else
    token_resp="$(
      curl -fsS --get "https://signin.aws.amazon.com/federation" \
        --data-urlencode "Action=getSigninToken" \
        --data-urlencode "Session=${session_json}"
    )" || {
      print -u2 -- "aws_console_url: failed to get SigninToken (HTTP/network error). Try: aws_console_url --debug"
      return 1
    }
  fi

  (( debug )) && print -u2 -- "aws_console_url debug: token_resp=${token_resp}"

  # Parse SigninToken from JSON response
  local signin_token
  signin_token="$(
    python3 -c 'import json,sys; print(json.loads(sys.argv[1])["SigninToken"])' \
      "$token_resp"
  )" || {
    print -u2 -- "aws_console_url: could not parse SigninToken. token_resp was: ${token_resp}"
    return 1
  }

  (( debug )) && print -u2 -- "aws_console_url debug: signin_token=${signin_token}"

  # URL-encode the destination
  local encoded_dest
  encoded_dest="$(
    python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' \
      "$dest"
  )" || return 1

  # Construct the final login URL
  local login_url="https://signin.aws.amazon.com/federation?Action=login&Destination=${encoded_dest}&SigninToken=${signin_token}"
  print -r -- "$login_url"

  if (( do_open )); then
    if command -v open >/dev/null 2>&1; then
      open "$login_url"
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$login_url" >/dev/null 2>&1 &
    else
      print -u2 -- "aws_console_url: can't open browser (need 'open' on macOS or 'xdg-open' on Linux)."
      return 2
    fi
  fi
}

# Convenience alias (use 'function' keyword to allow dash in name)
function aws-console { aws_console_url "$@"; }
