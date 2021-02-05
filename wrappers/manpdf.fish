function manpdf --description 'View a manual page as PDF'
    command -sq manpdf; or return 127

    set -l pdf (command manpdf -f $argv); or return
    if string match -q "/*" "$pdf"
        # Print the filename if connected remotely;
        # otherwise, open the PDF.
        echo "$pdf"

        if not set -q SSH_CONNECTION
            open "$pdf"
        end
    else
        # Because `manpdf -h` produces a non-filename but exits 0.
        return 0
    end
end
