#!/bin/bash

set -uo pipefail
# set -e
# set -x

function log {
	echo "gcrypt-install-test: $*"
}

# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# Test # 01: Version flag/argument
# ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
_VERSIONCMD_RAW_OUTPUT=$(git-remote-gcrypt -v)
_VERSIONCMD_EXIT_CODE=$?
log [DEBUG] _VERSIONCMD_EXIT_CODE=$_VERSIONCMD_EXIT_CODE
log [DEBUG] _VERSIONCMD_RAW_OUTPUT=\'$_VERSIONCMD_RAW_OUTPUT\'

_VERSIONCMD_PARSE1=$(echo "$_VERSIONCMD_RAW_OUTPUT" | awk '{print $3,$4}' | xargs -r)
_VERSIONCMD_PARSE2_MATCHES=$(echo "$_VERSIONCMD_PARSE1" | grep '@@DEV_VERSION@@')
log [DEBUG] _VERSIONCMD_PARSE2_MATCHES=\'$_VERSIONCMD_PARSE2_MATCHES\'

if [ "$_VERSIONCMD_EXIT_CODE" -ne 0 ]; then
	log [ERROR] exiting due to earlier failures.
	exit 1
elif [ "$_VERSIONCMD_PARSE2_MATCHES" ]; then
	log [ERROR] Unexpectedly saw @@DEV_VERSION@@!
	exit 1
else
	log OK. Version test as expected.
fi
