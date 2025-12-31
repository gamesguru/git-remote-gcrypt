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

echo "Uninstallation complete."
