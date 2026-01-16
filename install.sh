#!/bin/sh
set -e

# Auto-detect Termux: if /usr/local doesn't exist but $PREFIX does (Android/Termux)
if [ -z "${prefix:-}" ]; then
	if [ -d /usr/local ]; then
		prefix=/usr/local
	elif [ -n "${PREFIX:-}" ] && [ -d "$PREFIX" ]; then
		# Termux sets $PREFIX to /data/data/com.termux/files/usr
		prefix="$PREFIX"
		echo "Detected Termux environment, using prefix=$prefix"
	else
		prefix=/usr/local
	fi
fi
: "${DESTDIR:=}"

log() { printf "\033[1;36m[INSTALL] %s\033[0m\n" "$1"; }
verbose() { echo "$@" >&2 && "$@"; }

install_v() {
	# Install $1 into $2/ with mode $3
	if ! verbose install -d "$2"; then
		echo "Error: Failed to create directory $2" >&2
		exit 1
	fi
	if ! verbose install -m "$3" "$1" "$2"; then
		echo "Error: Failed to install $1 into $2" >&2
		exit 1
	fi
}

# --- VERSION DETECTION ---
: "${OS_RELEASE_FILE:=/etc/os-release}"
if [ -f "$OS_RELEASE_FILE" ]; then
	# shellcheck disable=SC1091,SC1090
	. "$OS_RELEASE_FILE"
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
VERSION="$VERSION ($OS_IDENTIFIER)"

echo "Detected version: $VERSION"

# Setup temporary build area
BUILD_DIR="./.build_tmp"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Placeholder injection
sed "s|@@DEV_VERSION@@|$VERSION|g" git-remote-gcrypt >"$BUILD_DIR/git-remote-gcrypt"

# --- GENERATION ---
verbose ./utils/gen_docs.sh

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
