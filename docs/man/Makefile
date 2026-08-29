# Install the dots manpages into a local manpath.
#
# Usage:
#   make            Check every page renders (mandoc -T lint)
#   make install    Symlink pages into MANDIR (default ~/.local/share/man/man1)
#   make uninstall  Remove the symlinks
#
# Pages are symlinked (not copied) so they stay in sync with the repo; a later
# `cd ~/.dots && git pull` updates the manpages with no re-install. If man does
# not find them (macOS man(1) omits ~/.local/share/man from its default path on
# some versions), either set MANPATH or copy them to a manpath you already have:
#   make install MANDIR=/usr/local/share/man/man1
#
# On macOS, mandoc(1) is the system roff renderer; groff is not required.

MANDIR ?= $(HOME)/.local/share/man/man1
PAGES := $(wildcard dots-*.1)

.PHONY: all check install uninstall

all: check

check:
	@mandoc -T lint $(PAGES)
	@echo "check: $(words $(PAGES)) page(s) lint clean"

install: check
	@mkdir -p $(MANDIR)
	@for p in $(PAGES); do ln -sf $$(pwd)/$$p $(MANDIR)/$$p; done
	@echo "Installed $(words $(PAGES)) page(s) to $(MANDIR)."
	@if ! man -w dots-setup >/dev/null 2>&1; then \
		echo "NOTE: man(1) does not resolve dots-setup from $(MANDIR)."; \
		echo "Either export MANPATH=\"$(patsubst %/man1,%,$(MANDIR)):\$$MANPATH\" or re-run with:"; \
		echo "  make install MANDIR=<a manpage dir already in your manpath>/man1"; \
	fi

uninstall:
	@for p in $(PAGES); do rm -f $(MANDIR)/$$p; done
	@echo "Removed dots pages from $(MANDIR)"