#!/bin/bash
set -efuC -o pipefail
shopt -s inherit_errexit

# Helpers
print_info() { printf "\033[1;36m%s\033[0m\n" "$1"; }
print_success() { printf "\033[1;34m✓ %s\033[0m\n" "$1"; }
print_warn() { printf "\033[1;33m%s\033[0m\n" "$1"; }
print_err() { printf "\033[1;31m%s\033[0m\n" "$1"; }

# Settings
num_commits=5
files_per_commit=3
random_source="/dev/urandom"
random_data_per_file=1024 # Reduced size for faster testing (1KB)
default_branch="main"
test_user_name="Gcrypt Test User"
test_user_email="gcrypt-test@example.com"
pack_size_limit="12m" 

# Setup Sandbox
tempdir=$(mktemp -d)
trap 'rm -rf "$tempdir"' EXIT
print_info "Running in sandbox: $tempdir"

# --- KEY GENERATION ---
# We need to generate keys such that the target key is "buried" deep in the keyring.
# The bug occurs when GPG tries many keys and fails on earlier ones with a checksum error.
# We will generate 18 keys.
# Key 1..17: Decoys (Ed25519) - will be tried and fail (or trigger checksum error).
# Key 18: Target (Ed25519) - the one we actually encrypt to.

gpg_home="${tempdir}/gpg-home"
mkdir -p "$gpg_home"
chmod 700 "$gpg_home"
export GNUPGHOME="$gpg_home"

# Create a minimal gpg.conf to avoid randomness issues and ensure consistency
cat >"${gpg_home}/gpg.conf" <<EOF
use-agent
pinentry-mode loopback
no-tty
EOF

cat >"${gpg_home}/gpg-agent.conf" <<EOF
allow-loopback-pinentry
EOF

print_info "Step 1: Generating 18 Ed25519 keys (this may take a moment)..."
num_keys=18
for i in $(seq 1 $num_keys); do
	# Generate simple Ed25519 key (fast, no expiration)
	# We use a batch file for speed and non-interactivity
	cat >"${tempdir}/gen-key-${i}.batch" <<EOF
%echo Generating key $i...
Key-Type: EDDSA
Key-Curve: ed25519
Key-Usage: sign
Subkey-Type: ECDH
Subkey-Curve: cv25519
Name-Real: git-remote-gcrypt${i}
Name-Email: gcrypt${i}@example.com
Expire-Date: 0
%no-protection
%commit
EOF
	gpg --batch --generate-key "${tempdir}/gen-key-${i}.batch" >/dev/null 2>&1
done

print_info "Step 2: Collecting fingerprints..."
key_fps=()

# Capture fingerprints
# Integrated fix: use mapfile
#
# CRITICAL FIX:
# Previously, `grep fpr` captured both the Primary Key (EDDSA) and the Subkey (ECDH) fingerprints.
# This caused the `key_fps` array to double in size (36 entries for 18 keys).
# As a result, `key_fps[17]` (intended to be the last Primary Key) actually pointed to the
# Subkey of the 9th key (`key_fps[8*2 + 1]`).
# We configured `gcrypt.participants` with this Subkey, but GPG always signs with the Primary Key.
# This caused a signature mismatch ("Participant A vs Signer B") and verification failure.
# Using `awk` to filter `pub:` ensures we only capture the Primary Key.
mapfile -t key_fps < <(gpg --list-keys --with-colons | awk -F: '/^pub:/ {getline; print $10}')
echo "Generated keys: ${key_fps[*]}" | indent

###
section_break

# Setup Git
export GIT_AUTHOR_NAME="$test_user_name"
export GIT_AUTHOR_EMAIL="$test_user_email"
export GIT_COMMITTER_NAME="$test_user_name"
export GIT_COMMITTER_EMAIL="$test_user_email"

print_info "Step 3: Creating repository structure..."
mkdir "${tempdir}/first"
(
	cd "${tempdir}/first"
	git init -q -b "$default_branch"
	echo "content" >file.txt
	git add file.txt
	git commit -q -m "Initial commit"
)

# Prepare Remote Gcrypt Repo
# We use the file:// backend which just needs a directory.
# But for gcrypt::, we essentially push to a directory that becomes the encrypted store.
mkdir -p "${tempdir}/second.git"

print_info "Step 4: Pushing with SINGULAR participant (Key 2) to bury it..."
# We explicitly set ONLY the LAST key as the participant.
# This forces GPG to skip the first (num_keys-1) keys.
last_key_idx=$((num_keys - 1))
git config gcrypt.participants "${key_fps[last_key_idx]}"
git push -f "gcrypt::${tempdir}/second.git#${default_branch}" "${default_branch}"
) 2>&1
} | indent


print_info "Step 5: Cloning back - EXPECTING GPG TO ITERATE..."
# Now we try to clone (pull). GPG will have to decrypt the manifest.
# Since we have 18 keys in our keyring, and the message is encrypted to Key #18,
# GPG will try Key 1, 2... 17.
#
# With the BUG: GPG encounters a checksum error (due to ECDH/Ed25519 issues in some GPG versions with anonymous/multi-key handling) on an earlier key and ABORTS properly checking the others. git-remote-gcrypt sees the exit code 2 and dies.
#
# With the FIX: git-remote-gcrypt ignores the intermediate error and lets GPG continue until it finds Key 18.
output_file="${tempdir}/output.log"
(
	cd "${tempdir}"
	# We must force GPG to try keys.
	# Actually, GPG tries all secret keys for which it has an encrypted session key packet.
	# Since we are the participant, it should just find it.
	# BUT, the bug (Debian #885770 / GnuPG T3597) was that *anonymous* recipients (gpg -R) cause this iteration to be fragile.
	# gcrypt defaults to -R (anonymous).
	
	git clone "gcrypt::${tempdir}/second.git#${default_branch}" "third"
) >"${output_file}" 2>&1
ret=$?

print_info "Step 6: Reproduction Step - Clone with buried key..."
cat "${output_file}"

if grep -q "Checksum error" "${output_file}" && [ $ret -ne 0 ]; then
	print_warn "BUG(REPRODUCED): GPG Checksum error detected AND Clone failed!"
	exit 1
elif grep -q "Checksum error" "${output_file}" && [ $ret -eq 0 ]; then
	print_success "SUCCESS: Checksum error detected but Clone SUCCEEDED. (Fix is working!)"
elif [ $ret -eq 0 ]; then
	print_warn "WARNING: Test passed unexpectedly (Checksum error NOT detected at all). Bug trigger might be absent."
else
	print_warn "WARNING: Clone failed with generic error (Checksum error not detected)."
fi

# Continue to verify content.
echo "Verifying content match..."
assert diff -r --exclude ".git" -- "${tempdir}/first" "${tempdir}/third" 2>&1 | indent
} | indent

print_info "Step 7: Reproduction Step - Push with buried key..."
(
	cd "${tempdir}/third"
	echo "new data" >"new_file"
	git add "new_file"
	git commit -q -m "Commit for Step 7"
	git push "gcrypt::${tempdir}/second.git#${default_branch}" "${default_branch}"
) >"${output_file}" 2>&1
ret=$?

print_info "Step 7: Reproduction Step - Push with buried key..."
cat "${output_file}"

if grep -q "Checksum error" "${output_file}" && [ $ret -ne 0 ]; then
	print_warn "BUG(REPRODUCED): GPG Checksum error detected (Push) AND Push failed!"
	exit 1
elif grep -q "Checksum error" "${output_file}" && [ $ret -eq 0 ]; then
	print_success "SUCCESS: Checksum error detected (Push) but Push SUCCEEDED. (Fix is working!)"
elif [ $ret -eq 0 ]; then
	print_warn "WARNING: Push passed unexpectedly (Checksum error NOT detected at all)."
else
	print_warn "WARNING: Push failed with generic error (Checksum error not detected)."
fi
} | indent
