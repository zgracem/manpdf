# manpdf

Everyone(?) knows the trick where you pipe PostScript output from `man(1)`
to create a nice-looking PDF. But here's what that PDF *doesn't* have:

- Bookmarks, so you can use your PDF viewer's Table of Contents feature
  to find the section you're looking for.
- A permanent home, so you don't have to re-generate the same PDF over
  and over again.
- Metadata, so you can, you know... have metadata.

It's the future. Treat yourself to a nicer-looking man page.

![screenshot](https://github.com/zgracem/manpdf/blob/master/manpdf.png?raw=true)

## Installation

1. Clone this repository somewhere.
2. Move `~/somewhere/manpdf/manpdf.sh` to `~/bin/manpdf`, or somewhere else 
   in your `PATH`.
3. Add `~/somewhere/manpdf/_manpdf.bash` to your `.bashrc` for a handy wrapper
   function.

## Usage

* `manpdf bash` creates `$MANPDF_DIR/bash.1.pdf` if it doesn't exist.
  (`MANPDF_DIR` defaults to `~/.manpath`.)
* `manpdf -f bash` re-creates the PDF, even if it already exists.
  (Useful after a software upgrade updates the man page.)
* You can also search specific sections of the manual: `manpdf 3 printf`.

## Source code

The script is [thoroughly documented][src] in the comments.

[src]: https://github.com/zgracem/manpdf/blob/master/manpdf.sh

## Say hello

[zgm&#x40;inescapable&#x2e;org](mailto:zgm%40inescapable%2eorg)
