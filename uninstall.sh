#!/bin/sh
set -e

: "${prefix:=/usr/local}"
: "${DESTDIR:=}"

verbose() { echo "$@" >&2 && "$@"; }

BIN_PATH="$DESTDIR$prefix/bin/git-remote-gcrypt"
MAN_PATH="$DESTDIR$prefix/share/man/man1/git-remote-gcrypt.1.gz"

echo "Uninstalling git-remote-gcrypt..."

if [ -f "$BIN_PATH" ]; then
	verbose rm -f "$BIN_PATH"
	echo "Removed binary: $BIN_PATH"
else
	echo "Binary not found: $BIN_PATH"
fi

if [ -f "$MAN_PATH" ]; then
	verbose rm -f "$MAN_PATH"
	echo "Removed man page: $MAN_PATH"
else
	echo "Man page not found: $MAN_PATH"
fi

# Completions
COMP_BASH="$DESTDIR$prefix/share/bash-completion/completions/git-remote-gcrypt"
COMP_ZSH="$DESTDIR$prefix/share/zsh/site-functions/_git-remote-gcrypt"
COMP_FISH="$DESTDIR$prefix/share/fish/vendor_completions.d/git-remote-gcrypt.fish"

for f in "$COMP_BASH" "$COMP_ZSH" "$COMP_FISH"; do
	if [ -f "$f" ]; then
		verbose rm -f "$f"
		echo "Removed completion: $f"
	fi
done

echo "Uninstallation complete."
