atlas_aws_kaleidoscope() {
  local role="${1:-1}"
  source <(
    printf '%s\n' "$role" | atlas cloudtoken aws --auth-method=iic -f Kaleidoscope -f Administrator -o bash 2>&1 \
      | sed -n '/^export /,$p'
  )
}
