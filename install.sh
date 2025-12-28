#!/bin/bash
set -efuC -o pipefail

: ${prefix:=/usr/local}
: ${DESTDIR:=}

verbose() { echo "$@" >&2 && "$@"; }

install_v() {
    # Install $1 into $2/ with mode $3
    verbose install -d "$2" &&
    verbose install -m "$3" "$1" "$2"
}

# 1. Load OS identity
if [ -f /etc/os-release ]; then
	source /etc/os-release
fi

# 2. Combine ID and ID_LIKE into a single searchable list
# Arch: "arch"
# RHEL: "rhel fedora"
# Debian: "debian"
SEARCH_LIST=$(echo "${ID:-} ${ID_LIKE:-}" | xargs)

VERSION=""

# 3. Split the list and loop over each element
for distro in $SEARCH_LIST; do
	case "$distro" in
	fedora | rhel)
		if [ -f redhat/git-remote-gcrypt.spec ]; then
			VER_NUM=$(awk '/^Version:/ {print $2}' redhat/git-remote-gcrypt.spec)
			VERSION="$VER_NUM (redhat)"
			break
		fi
		;;
	debian | ubuntu)
		if [ -f debian/changelog ]; then
			VER_NUM=$(head -n 1 debian/changelog | cut -d ' ' -f 2 | tr -d '()')
			VERSION="$VER_NUM (debian)"
			break
		fi
		;;
	arch)
		# Query pacman for the version of the already installed package
		VER_NUM=$(pacman -Q git-remote-gcrypt 2>/dev/null | awk '{print $2}')
		if [ -n "$VER_NUM" ]; then
			VERSION="$VER_NUM (arch)"
			break
		else
			# If not installed, use a placeholder so the script doesn't exit 1
			VERSION="devel (arch)"
			break
		fi
		;;
	esac
done

# 4. Strict Exit: If no supported metadata matched the OS identity
if [ -z "$VERSION" ]; then
	echo "❌ ERROR: No supported distribution found in ID/ID_LIKE: '$SEARCH_LIST'." >&2
	exit 1
fi

echo "Detected version: $VERSION"

# 5. Inject and Install
# Use a temp directory to prepare the file
BUILD_DIR="./.build_tmp"
mkdir -p "$BUILD_DIR"
trap 'rm -rf "$BUILD_DIR"' EXIT

# Inject the full version string into the placeholder
sed "s/@@DEV_VERSION@@/$VERSION/g" git-remote-gcrypt >"$BUILD_DIR/git-remote-gcrypt"

# Install the modified file
install_v "$BUILD_DIR/git-remote-gcrypt" "$DESTDIR$prefix/bin" 755
# --- END VERSION DETECTION ---

if command -v rst2man >/dev/null; then
	rst2man='rst2man'
elif command -v rst2man.py >/dev/null; then # it is installed as rst2man.py on macOS
	rst2man='rst2man.py'
fi

if [ -n "$rst2man" ]; then
	# Update trap to clean up manpage too
	trap 'rm -rf "$BUILD_DIR"; rm -f git-remote-gcrypt.1.gz' EXIT
	verbose $rst2man ./README.rst | gzip -9 >git-remote-gcrypt.1.gz
	install_v git-remote-gcrypt.1.gz "$DESTDIR$prefix/share/man/man1" 644
else
	echo "'rst2man' not found, man page not installed" >&2
fi
