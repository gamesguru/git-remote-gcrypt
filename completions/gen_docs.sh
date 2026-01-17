#!/bin/bash
set -e

# gen_docs.sh
# Generates documentation and shell completions from git-remote-gcrypt source.
# Strictly POSIX sh compliant.

SCRIPT_KEY="HELP_TEXT"
SRC="git-remote-gcrypt"
README_TMPL="completions/templates/README.rst.in"
README_OUT="README.rst"
BASH_TMPL="completions/templates/bash.in"
BASH_OUT="completions/bash/git-remote-gcrypt"
ZSH_TMPL="completions/templates/zsh.in"
ZSH_OUT="completions/zsh/_git-remote-gcrypt"
FISH_TMPL="completions/templates/fish.in"
FISH_OUT="completions/fish/git-remote-gcrypt.fish"

# Ensure we're in the project root
if [ ! -f "$SRC" ]; then
	echo "Error: Must be run from project root" >&2
	exit 1
fi

# Extract HELP_TEXT variable content
# Using sed to capture lines between double quotes of HELP_TEXT="..."
# Assumes HELP_TEXT="..." is a single block.
RAW_HELP=$(sed -n "/^$SCRIPT_KEY=\"/,/\"$/p" "$SRC" | sed "s/^$SCRIPT_KEY=\"//;s/\"$//")

# 1. Prepare {commands_help} for README (Indented for RST)
# We want the Options and Git Protocol Commands sections
COMMANDS_HELP=$(printf '%s\n' "$RAW_HELP" | sed -n '/^Options:/,$p' | sed 's/^/    /')

# 2. Parse Commands and Flags for Completions
# Extract command names (first word after 2 spaces)
COMMANDS_LIST=$(echo "$RAW_HELP" | awk '/^  [a-z]+ / {print $1}' | grep -vE "^(help|version|capabilities|list|push|fetch)$" | sort | tr '\n' ' ' | sed 's/ $//')

# Extract clean flags
# Text: "    clean -f, --force    Actually delete files..."
# We want to extract flags properly.
# Get lines, then extract words starting with -
# Stop at the first word that doesn't start with - (description start)
CLEAN_FLAGS_RAW=$(echo "$RAW_HELP" | grep "^    clean -" | awk '{
	out=""
	for (i=2; i<=NF; i++) {
		if ($i ~ /^-/) {
			# remove comma if present
			sub(",", "", $i)
			out = out ? out " " $i : $i
		} else {
			break
		}
	}
	print out
}')

CLEAN_FLAGS_BASH=$(echo "$CLEAN_FLAGS_RAW" | tr '\n' ' ' | sed 's/  */ /g; s/ $//')

# For Zsh: Generate proper spec strings
# Use while read loop to handle lines safely
CLEAN_FLAGS_ZSH=$(echo "$CLEAN_FLAGS_RAW" | while read -r line; do
	[ -z "$line" ] && continue
	# line is "-f --force" or "--hard"
	# simple split
	flags=$(echo "$line" | tr ' ' '\n')
	# Build exclusion list (all flags in this group exclude each other self, but wait,
	# usually -f and --force are the same.
	# The user wants: '(-f --force)'{-f,--force}'[desc]'

	# Check if we have multiple flags (aliases)
	if echo "$line" | grep -q " "; then
		# "(-f --force)"
		excl="($line)"
		# "{-f,--force}"
		fspec="{$(echo "$line" | sed 's/ /,/g')}"
	else
		# "" (no exclusion needed against itself strictly, or just empty for single)
		# But usually clean flags are distinct.
		excl=""
		fspec="$line"
	fi

	# Description - specific descriptions would be better, but generic for now.
	# We rely on the fact that these are clean flags.
	desc="[Flag]"

	# Use printf to avoid newline issues in variable
	# Zsh format: '(-f --force)'{-f,--force}'[Actually delete files]'
	if [ -n "$excl" ]; then
		printf "'%s'%s'%s'" "$excl" "$fspec" "$desc"
	else
		printf "%s'%s'" "$fspec" "$desc"
	fi
done | tr '\n' ' ')

# For Fish
# We need to turn "-f --force" into: -s f -l force
# And "--hard" into: -l hard
CLEAN_FLAGS_FISH=$(echo "$CLEAN_FLAGS_RAW" | while read -r line; do
	[ -z "$line" ] && continue

	short=""
	long=""

	# Split by space
	# Case 1: "-f --force" -> field1=-f, field2=--force
	f1=$(echo "$line" | awk '{print $1}')
	f2=$(echo "$line" | awk '{print $2}')

	# Description is looked up separately via grep because it contains spaces
	# escape single quotes for Fish string
	desc=$(echo "$RAW_HELP" | grep -F -- "$line" | head -n 1 | sed 's/^[[:space:]]*//' | cut -d ' ' -f 3- | sed "s/'/\\\\'/g")

	if [[ $f1 == -* ]] && [[ $f2 == --* ]]; then
		short="${f1#-}"
		long="${f2#--}"
	elif [[ $f1 == --* ]]; then
		long="${f1#--}"
	else
		# Starts with - (short)
		short="${f1#-}"
		if [ -n "$f2" ] && echo "$f2" | grep -q "^--"; then
			long="${f2#--}"
		fi
	fi

	cmd='complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from clean"'
	[ -n "$short" ] && cmd="$cmd -s $short"
	[ -n "$long" ] && cmd="$cmd -l $long"
	cmd="$cmd -d '$desc'"

	printf "%s\n" "$cmd"
done)

# 3. Generate README
echo "Generating $README_OUT..."
# Escape backslashes, forward slashes, and ampersands, then flatten newlines to \n
ESCAPED_HELP=$(printf '%s\n' "$COMMANDS_HELP" | sed 's/\\/\\\\/g; s/[\/&]/\\&/g' | awk 'NR>1{printf "\\n"} {printf "%s", $0}')
sed "s/{commands_help}/$ESCAPED_HELP/" "$README_TMPL" >"$README_OUT"

# 4. Generate Bash
echo "Generating Bash completions..."
sed "s/{commands}/$COMMANDS_LIST/; s/{clean_flags_bash}/$CLEAN_FLAGS_BASH/" "$BASH_TMPL" >"$BASH_OUT"

# 5. Generate Zsh
echo "Generating Zsh completions..."
# Zsh substitution is tricky with the complex string.
# We'll stick to replacing {commands} and {clean_flags_zsh}
# Need to escape special chars for sed
SAFE_CMDS=$(echo "$COMMANDS_LIST" | sed 's/ / /g') # just space separated
# For clean_flags_zsh, since it contains quotes and braces, we need care.
# We'll read the template line by line? No, sed is standard.
# We use a temp file for the replacement string to avoid sed escaping hell for large blocks?
# Or just keep it simple.
sed "s/{commands}/$COMMANDS_LIST/" "$ZSH_TMPL" \
	| sed "s|{clean_flags_zsh}|$CLEAN_FLAGS_ZSH|" >"$ZSH_OUT"

# 6. Generate Fish
echo "Generating Fish completions..."
# Fish needs {not_sc_list} which matches {commands} (space separated)
# Use awk for safe replacement of multi-line string
CLEAN_FLAGS_FISH="$CLEAN_FLAGS_FISH" awk -v cmds="$COMMANDS_LIST" '
	BEGIN { flags=ENVIRON["CLEAN_FLAGS_FISH"] }
	{
		gsub(/{not_sc_list}/, cmds)
		gsub(/{clean_flags_fish}/, flags)
		print
	}
' "$FISH_TMPL" >"$FISH_OUT"

echo "Done."
