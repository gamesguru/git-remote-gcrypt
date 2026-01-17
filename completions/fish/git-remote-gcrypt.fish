# Fish completion for git-remote-gcrypt
# Install to: ~/.config/fish/completions/

complete -c git-remote-gcrypt -s h -l help -d 'Show help message'
complete -c git-remote-gcrypt -s v -l version -d 'Show version information'

# Subcommands
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from check clean stat" -a 'check' -d 'Check if URL is a gcrypt repository'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from check clean stat" -a 'clean' -d 'Scan/Clean unencrypted files from remote'
complete -c git-remote-gcrypt -f -n "not __fish_seen_subcommand_from check clean stat" -a 'stat' -d 'Show diagnostics'
complete -c git-remote-gcrypt -n "__fish_seen_subcommand_from clean" -a "(git remote -v 2>/dev/null | grep 'gcrypt::' | awk '{print \$1}' | sort -u)" -d 'Gcrypt Remote'
complete -c git-remote-gcrypt -n "__fish_seen_subcommand_from check" -a "(git remote 2>/dev/null)" -d 'Git Remote'
complete -c git-remote-gcrypt -n "__fish_seen_subcommand_from stat" -a "(git remote 2>/dev/null)" -d 'Git Remote'

# Clean flags
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from clean" -s -force -l  -d 'Flag';
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from clean" -s -init -l  -d 'Flag';
complete -c git-remote-gcrypt -f -n "__fish_seen_subcommand_from clean" -s -hard -l  -d 'Flag';

