#!/bin/sh
set -e

: "${prefix:=/usr/local}"
: "${DESTDIR:=}"

verbose() { echo "$@" >&2 && "$@"; }

install_v() {
	# Install $1 into $2/ with mode $3
	verbose install -d "$2" \
		&& verbose install -m "$3" "$1" "$2"
}

# --- VERSION DETECTION ---
if [ -f /etc/os-release ]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	OS_IDENTIFIER=$ID # Linux
elif command -v uname >/dev/null; then
	# Fallback for macOS/BSD (darwin)
	OS_IDENTIFIER=$(uname -s | tr '[:upper:]' '[:lower:]')
else
	OS_IDENTIFIER="unknown_OS"
fi

# Get base version then append OS identifier
if [ -d .git ] && command -v git >/dev/null; then
	VERSION=$(git describe --tags --always --dirty 2>/dev/null || git rev-parse --short HEAD 2>/dev/null || echo "dev")
else
	if [ ! -f debian/changelog ]; then
		echo "Error: debian/changelog not found (and not a git repo)" >&2
		exit 1
	fi
	VERSION=$(grep ^git-remote-gcrypt debian/changelog | head -n 1 | awk '{print $2}' | tr -d '()')
fi
VERSION="$VERSION (deb running on $OS_IDENTIFIER)"

echo "Detected version: $VERSION"

# Setup temporary build area
BUILD_DIR="./.build_tmp"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Placeholder injection
sed "s|@@DEV_VERSION@@|$VERSION|g" git-remote-gcrypt >"$BUILD_DIR/git-remote-gcrypt"

# --- GENERATION ---
verbose python3 completions/gen_docs.py

# --- INSTALLATION ---
# This is where the 'Permission denied' happens if not sudo
install_v "$BUILD_DIR/git-remote-gcrypt" "$DESTDIR$prefix/bin" 755

if command -v rst2man >/dev/null; then
	rst2man='rst2man'
elif command -v rst2man.py >/dev/null; then # it is installed as rst2man.py on macOS
	rst2man='rst2man.py'
fi

if [ -n "$rst2man" ]; then
	# Update trap to clean up manpage too
	trap 'rm -rf "$BUILD_DIR"; rm -f git-remote-gcrypt.1.gz' EXIT
	verbose "$rst2man" ./README.rst | gzip -9 >git-remote-gcrypt.1.gz
	install_v git-remote-gcrypt.1.gz "$DESTDIR$prefix/share/man/man1" 644
else
	echo "'rst2man' not found, man page not installed" >&2
fi

# Install shell completions
# Bash
install_v completions/bash/git-remote-gcrypt "$DESTDIR$prefix/share/bash-completion/completions" 644
# Zsh
install_v completions/zsh/_git-remote-gcrypt "$DESTDIR$prefix/share/zsh/site-functions" 644
# Fish
install_v completions/fish/git-remote-gcrypt.fish "$DESTDIR$prefix/share/fish/vendor_completions.d" 644

echo "Installation complete!"
echo "Completions installed to $DESTDIR$prefix/share/"
