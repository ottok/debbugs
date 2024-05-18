#!/usr/bin/make -f

all: debbugs_logo.svg debbugs_logo_icon.png

## if you want to modify debbugs_logo.svg do the modifications to
## debbugs_logo_orig.svg, and then run make update_debbugs_logo and check the
## changes in.
update_debbugs_logo: debbugs_logo_orig.svg
	inkscape \
	--export-text-to-path --export-plain-svg debbugs_logo.svg $<;

## Note that the current logo and the original as not the same image due to
## unknown historical reasons. Both are now stored in version control, and this
## one is converted into a png file at build time and used as the website
## favicon.png at 32x32 pixels with is basically unviewable considering how much
## details have been crammed into the logo.
debbugs_logo_icon.png: debbugs_logo.svg
	convert $< -background white -resize 64x64 -flatten $@
