#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════════╗
# ║                     manpdf: Because you deserve it.                      ║
# ║                   Another fine shell script by Z.G.M.                    ║
# ║                          <inescapable.org/~zgm>                          ║
# ╟──────────────────────────────────────────────────────────────────────────╢
# ║ Everyone(?) knows the trick where you pipe PostScript output from man(1) ║
# ║ to create a nice-looking PDF. But here's what that PDF *doesn't* have:   ║
# ║                                                                          ║
# ║ - Bookmarks, so you can use your PDF viewer's Table of Contents feature  ║
# ║   to find the section you're looking for.                                ║
# ║ - A permanent home, so you don't have to re-generate the same PDF over   ║
# ║   and over again.                                                        ║
# ║ - Metadata, so you can, you know... have metadata.                       ║
# ║                                                                          ║
# ║ It's the future. Treat yourself to a nicer-looking man page.             ║
# ╚══════════════════════════════════════════════════════════════════════════╝

# MANPDF_DIR is the path to the directory where we will save generated PDFs.
# Set it in your environment (recommended), or configure it here.
if [[ -d $MANPDF_DIR ]]; then
  # This check will also fail if the variable is unset.
  readonly pdf_dir="$MANPDF_DIR"
else
  readonly pdf_dir="${HOME}/.manpdf"
fi

# Name of script to include in error messages.
readonly this="manpdf"

# Usage synopsis.
readonly usage="${this} [-f] [SECTION] PAGE"

# This shell setting causes pipes to return the rightmost non-zero (i.e. false)
# value in the command chain. Without this setting, `process_man_file` below
# would return true even if gunzip(1) failed to find/unzip the requested file.
set -o pipefail

# Required for some of the more elaborate `case` statements below.
shopt -s extglob

# -----------------------------------------------------------------------------
# Error handling
# -----------------------------------------------------------------------------

# `scold` prints its first argument to standard error. The `%b` format
# specifier to `printf` interprets escape sequences in the argument, so
# we can throw things like ANSI colour sequences in there if we want to.
# (Blinking green-on-red error messages with embedded BEL characters --
# everyone loves those, right?)
#
# It adds a newline to the end of the error message, but only if $message
# isn't empty -- pointless if calling `scold` directly, but prevents a blank
# line of output when calling `die` without arguments (see below).
scold()
{
  local message="${1}"
  printf >&2 "%b" "${message:+$message\n}"
}

# If called with a single, numerical argument, `die` exits the script with that
# exit status. Otherwise, it prints the 1st argument to standard error using
# `scold`, then exits with its 2nd argument as the status, or 1 if no second
# argument is specified. If called with no arguments, it functions like
# the builtin `exit`, terminating the script silently with the status of
# the final command.
#
# - Emit helpful debug messages! -> die "error in $BASH_SOURCE at $LINENO"
# - Preserve return values!      -> live_free || die "hard"
# - Don't panic, just exit.      -> die 42
die()
{
  local last_ret="${?}"
  local ret

  if [[ $1 == +([[:digit:]]) && $# -eq 1 ]]; then
    # If the first and only argument is a number, let us assume it's meant to
    # be an exit status, and use it immediately.
    exit "${1}"

  elif [[ $1 == "--" ]]; then
    # If you absolutely must print a bare numeral as your *totally unhelpful*
    # error message, you can use it like `die -- 42`, and it will print "42"
    # and exit with a status of 1, the default. But don't do that.
    shift
  fi

  if [[ $# -gt 0 ]]; then
    # Whatever's left as the first positional argument is our error message.
    # Prefix it with the script name, for that classy professional touch
    # when you break something.
    scold "${this:+$this: }${1}"

    # Use the second argument as the exit status, if present.
    # Otherwise, default to 1 -- failure.
    ret="${2:-1}"

  else
    # No arguments at all. If the exit status of the last command isn't zero,
    # use that. If it is -- well, this is an error handling function, so we're
    # defaulting to good old 1. If you want to exit 0, use `exit 0`.
    if (( last_ret > 0 )); then
      ret="${last_ret}"
    else
      ret=1
    fi
  fi

  exit "${ret}"
}

# -----------------------------------------------------------------------------
# Support functions
# -----------------------------------------------------------------------------

# We need GhostScript to convert groff(1)'s PostScript output to PDF. Enter
# `ghostscript_is_available`. It returns 0 if it finds `gs` in PATH, and 1 if
# it doesn't (which will cause the entire script to abort). We only need to
# mute standard out: `type -P` fails silently.
ghostscript_is_available()
{
  type -P "gs" >/dev/null
}

# `make_temp_dir` creates a temporary directory for our intermediate files.
# If successful, it prints the path to the new directory, to be captured like
# `tmp_dir=$(make_temp_dir)`, and returns mktemp(1)'s exit status regardless.
#
# The X's in $template will be replaced with a unique alphanumeric string
# like "4dyS3t". GNU's mktemp requires at least 3 X's at the end of the
# template, but BSD doesn't care -- it's your life, man. Take risks, live by
# your own rules.
#
# Anyway, `mktemp -d` gets us a directory instead of a file; `-t` is the old
# but portable(ish?) way to get $TMPDIR prepended to $template.
make_temp_dir()
{
  local template="${this}.XXXXXX"
  mktemp -d -t "${template}"
}

# `man_page_title` takes $manpage (the full path to an unformatted man page),
# and prints its "friendly" name, e.g. "printf(1)" or "sudo(8)" to stdout.
# While this can sometimes be trivially derived from the path itself, it can't
# always; the edge cases handled here are meant to reliably return what
# the page would be called colloquially, not necessarily what it's called in
# the file system.
#
# Since it gets its input from `man -w`, we know this function will only
# receive a valid, predictably-formatted path, which means we don't need to
# validate the input. And there's no error condition, so it always returns 0.
man_page_title()
{
  local manpage="${1}"    # input

  local title
  title="${manpage##*/}"  # Strip leading path from filename.
  title="${title%.gz}"    # Strip trailing ".gz" extension (if any).

  local section
  section="${title##*.}"  # Capture section number.
  title="${title%.*}"     # Remove section number from title.

  if [[ $section =~ (.+)(ssl|tcl)$ ]]; then
    section=${BASH_REMATCH[1]}
  elif [[ $section == 3o ]]; then
    section=3
  fi

  # The first argument to `printf` formats the title and section number.
  # The default is "%s.%s", since we're using it to generate a filename, but
  # you could change it to "%s(%s)" if "bash(1).pdf" would suit you better.
  printf "%s.%s" "$title" "$section"
}

# -----------------------------------------------------------------------------
# Document processing
# -----------------------------------------------------------------------------

# `process_man_file` takes two arguments: $man_path is the full path to an
# unformatted man page, as returned by `man -w` in Step 0; $processed_man_file
# specifies the output file, which will have metadata added by sed(1) for groff
# and pdfmark to use in Step 4. This function will return 0, except in the very
# unlikely case that gunzip can't find or decompress the file, when it will
# return gunzip's non-zero exit status.
process_man_file()
{
  local man_path="${1}"           # input
  local processed_man_file="${2}" # output

  # sed can't process a gzipped man file, so run it through gunzip first.
  # `gunzip -c` sends the decompressed file to standard output, leaving the
  # original file intact; when `-c` is combined with `-f`, gunzip will pass
  # non-gzipped files through unchanged instead of throwing an error.
  #
  # The first sed call implements these commands, in order:
  #   - Set PDF Title metadata from the man page's nicely-formatted title
  #     - Based on args to the man(7) `.TH` or mdoc(7) `.Dt` macro
  #   - Set PDF Subject metadata to the man page's short description
  #     - First try:  The line after the `.SH NAME` man macro
  #     - Second try: Args to the `.Nd` mdoc macro
  #   - Create 1st-level bookmarks for all 1st-level headings
  #     - From all mdoc `.Sh` or man `.SH` macros
  #   - Create 2nd-level bookmarks for all 2nd-level headings
  #     - From all `.SS` macros
  #   - Set PDF options (at top of file):
  #     - .pdfview /PageMode /UseOutlines <- Show bookmarks panel when opened
  #     -          /Page 1                <- Open to first page
  #     -          /View [/Fit]           <- Zoom to fit page to window
  #     - .nr PDFOUTLINE.FOLDLEVEL 1      <- Collapse all nested bookmarks
  #     - .nr PDFHREF.VIEW.LEADING 30.0p  <- Set bookmark targets 30 points
  #                                          above the text so the window won't
  #                                          cut it off
  #   - Call the `.pdfsync` macro to apply the metadata commands
  #
  # The second sed call removes unsightly and unnecessary escape sequences
  # from bookmark titles, which aren't present to be removed until the first
  # set of commands is complete, and converts arguments to the `.so` (source)
  # macro to absolute paths [test case: zshall(1)].

  gunzip -c -f "${man_path}" \
  | sed -E \
    -e 's#^\.(TH|Dt) "?(\S+)"? "?(\S+)"?#.pdfinfo /Title \L\2(\3)\E\n&#g' \
    -e '/^\.SH "?NAME"?/{n;s/^[^[:space:]]+ \\?- (.+)$/&\n.pdfinfo \/Subject \1/g;}' \
    -e 's#^\.Nd (.+)$#&\n.pdfinfo /Subject \1#g' \
    -e 's#^\.S[hH] (.+)$#.pdfbookmark 1 \1\n&#g' \
    -e 's#^\.SS (.+)$#.pdfbookmark 2 \1\n&#g' \
    -e '1s#.*#.pdfview /PageMode /UseOutlines /Page 1 /View [/Fit]\n.nr PDFOUTLINE.FOLDLEVEL 1\n.nr PDFHREF.VIEW.LEADING 30.0p\n&#' \
    -e '$s#.*#&\n.pdfsync#' \
  | sed -E \
    -e '/^\.pdfbookmark/s/\\?f[BIRP]//g' \
    -e '/^\.pdfbookmark/s/\\//g' \
    -e 's#^\.so ([^/].*)$#.so '"${man_path%/*}/../"'\1#p' \
  > "${processed_man_file}"

  # References: /usr/share/groff/1.19.2/tmac/pdfmark.tmac
  #             https://gnu.org/software/groff/manual/html_node/Man-usage.html
}

# `man_to_ps` takes two arguments: $man_file, the path to the modified document
# generated by `process_man_file` -- and $ps_file, which is rendered from
# $man_file by groff. This returns 0 if groff successfully creates a file, and
# groff's non-zero exit status otherwise.
man_to_ps()
{
  local man_file="${1}" # input
  local ps_file="${2}"  # output

  # groff options:
  #   -t          = Preprocess with tbl(1) -- needed for terminfo(5) et al.
  #   -Tps        = Selects the PostScript output device
  #   -m mandoc   = Loads the macro that handles man pages
  #   -m pdfmark  = Loads the macro that will process the metadata and
  #                 bookmarks we added earlier
  #   -c          = Disables colour output, because getting ANSI colours
  #                 into a PostScript file is considerably outside the scope
  #                 of this already-ambitious script
  groff -t -Tps -m mandoc -m pdfmark -c \
        "${man_file}" > "${ps_file}" \
    || return "${?}"

  # It's possible for groff to return 0 while failing to produce any output,
  # so we need to make sure $ps_file isn't empty before claiming success.
  if [[ -s $ps_file ]]; then
    # Never mind, we're cool.
    return 0
  else
    # The file is zero-length; groff must have failed.
    return 1
  fi
}

# `ps_to_pdf` uses GhostScript to turn $ps_file (its first argument) into
# $pdf_file (its second). On success, it returns 0; on failure, it returns
# GhostScript's exit status.
ps_to_pdf()
{
  local ps_file="${1}"  # input
  local pdf_file="${2}" # output

  # GhostScript options:
  #   -q        = Suppresses startup messages
  #   -dBATCH   = Suppresses other output too ("batch file mode")
  #   -dNOPAUSE = Disables the prompt and pause after each page
  if gs -q -dBATCH -dNOPAUSE -sDEVICE=pdfwrite \
        -sOutputFile="${pdf_file}" "${ps_file}"
  then
    return 0
  else
    # GhostScript failed, so return with its exit status.
    return "${?}"
  fi
}

# -----------------------------------------------------------------------------

main()
{
  if (( $# == 0 )); then
    # If invoked with no arguments, print a usage message on stderr and exit 1.
    die "Usage: ${usage}"
  elif [[ $1 == -@(h|-help) ]]; then
    # With `-h` or `--help`, print usage on standard output and, since they
    # asked nicely, exit 0.
    printf "Usage: %s\\n" "${usage}"
    exit 0
  elif [[ $1 == -@(f|-force) ]]; then
    # This script will not overwrite an existing PDF unless `-f|--force` is
    # given as the first argument, which you'd want to do after, e.g.,
    # a significant version jump makes the old PDF obsolete.
    readonly ok_to_clobber=1
    shift
  fi

  # ---------------------------------------------------------------------------
  # Step -1: Do we have GhostScript? We need GhostScript.
  # ---------------------------------------------------------------------------

  if ! ghostscript_is_available; then
    die "missing requirement: GhostScript"
  fi

  # ---------------------------------------------------------------------------
  # Step 0: Check whether there's a man page to render into PDF at all.
  # ---------------------------------------------------------------------------

  # If there is, we can implicitly trust the result, so there's no need to
  # validate the existence of the file ourselves.
  # If there's not, time to `die`, passing through man's stderr & exit status.
  local man_path
  man_path="$(man -w "${@}")" || die

  # ---------------------------------------------------------------------------
  # Step 1: Get the nicely-formatted title.
  # ---------------------------------------------------------------------------

  local title
  title="$(man_page_title "${man_path}")"

  # Set the path where our PDF will end up.
  local pdf_file="${pdf_dir}/${title}.pdf"

  # If there's already a PDF at that path, we'll only overwrite it if we got
  # told to `-f/--force` it earlier.
  if [[ ! -f $pdf_file ]] || [[ -n $ok_to_clobber ]]; then

    # -------------------------------------------------------------------------
    # Step 2: Set up our temporary directory.
    # -------------------------------------------------------------------------

    local tmp_dir
    if tmp_dir="$(make_temp_dir)"; then
      # Our unformatted man page with pdfmark inserts:
      local man_file
      man_file="${tmp_dir}/${title}"

      # Our PostScript file with extra PDF instructions:
      local ps_file
      ps_file="${tmp_dir}/${title}.ps"
    else

      # The absence of this directory is, how you say... une dealbreaker.
      # Au revoir. *slinks into foggy Parisian night*
      die "cannot continue without temporary directory"
    fi

    # -------------------------------------------------------------------------
    # Step 3: Add macros to man file.
    # -------------------------------------------------------------------------

    # If this fails, which it probably won't, it will exit w/ gunzip's status.
    process_man_file "${man_path}" "${man_file}" \
      || die "failed to add macros to ${man_file}"

    # -------------------------------------------------------------------------
    # Step 4: Generate the PostScript file.
    # -------------------------------------------------------------------------

    # If this fails badly, it will return groff's exit status. Unfortunately,
    # groff has no mechanism to validate its output, so it may return "success"
    # having generated an invalid PostScript file. For slightly more info, see
    # https://lists.gnu.org/archive/html/bug-groff/2015-10/msg00008.html.
    man_to_ps "${man_file}" "${ps_file}" \
      || die "failed to generate PostScript file for ${title}"

    # -------------------------------------------------------------------------
    # Step 5: Generate a PDF from the PostScript output.
    # -------------------------------------------------------------------------

    # If this fails -- possibly because of bad data from Step 4 -- it will exit
    # with GhostScript's status. Fair warning: if `gs` has meaningful error
    # statuses at all, they seem to be undocumented.
    ps_to_pdf "${ps_file}" "${pdf_file}" \
      || die "failed to generate PDF from ${ps_file}"
  fi

  # ---------------------------------------------------------------------------
  # Step 6: ~ fin ~
  # ---------------------------------------------------------------------------
  # By the time we've reached this point, the PDF definitely exists. Print the
  # path so we can find it (or write a wrapper function to open a PDF viewer,
  # or Snapchat it to a Vine, or whatever the kids are doing these days).
  echo "${pdf_file}"
}

main "$@"
