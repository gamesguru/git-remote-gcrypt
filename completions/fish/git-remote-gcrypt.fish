# Fish completion for git-remote-gcrypt
# Install to: ~/.config/fish/completions/

complete -c git-remote-gcrypt -s h -l help -d 'Show help message'
complete -c git-remote-gcrypt -s v -l version -d 'Show version information'
complete -c git-remote-gcrypt -l check -d 'Check if URL is a gcrypt repository' -r -F

# Git protocol commands
complete -c git-remote-gcrypt -f -a 'capabilities' -d 'Show git remote helper capabilities'
complete -c git-remote-gcrypt -f -a 'list' -d 'List refs in remote repository'
complete -c git-remote-gcrypt -f -a 'push' -d 'Push refs to remote repository'
complete -c git-remote-gcrypt -f -a 'fetch' -d 'Fetch refs from remote repository'
