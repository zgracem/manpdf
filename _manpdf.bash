manpdf()
{
  local pdf; pdf=$(command manpdf "$@") || return

  # Because `manpdf -h` produces a non-filename but exits 0.
  if [[ ${pdf:0:1} != "/" ]]; then
    echo "$pdf"
    return 0
  fi

  # Print the filename if connected remotely; otherwise, open the PDF.
  if [[ -n $SSH_CONNECTION ]]; then
    echo "$pdf"
  else
    open "$pdf"
  fi
}
