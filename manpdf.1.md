manpdf(1) -- generate a nice-looking man page
=============================================

## SYNOPSIS

`manpdf` [-f|--force] [<section>] <name>

## DESCRIPTION

Everyone(?) knows the trick where you pipe PostScript output from `man(1)`
to create a nice-looking PDF. But here's what that PDF _doesn't_ have:

- Bookmarks, so you can use your PDF viewer's Table of Contents feature
  to find the section you're looking for.
- A permanent home, so you don't have to re-generate the same PDF over
  and over again.
- Metadata, so you can, you know... have metadata.

It's the future. Treat yourself to a nicer-looking man page.

## OPTIONS

  * `-f`, `--force`:
    Force a rebuild of the PDF man page, even if it already exists.

  * `-h`, `--help`:
    Print usage on standard output.

## ENVIRONMENT

By default, `manpdf` stores its generated PDFs in `~/.manpdf`. You can override
this by setting `MANPDF_DIR` in your environment.

## REQUIREMENTS

- [GhostScript](https://www.ghostscript.com/)

## SEE ALSO

man(1), groff(1), groff(7), gs(1)

## HOMEPAGE

<https://github.com/zgracem/manpdf>
