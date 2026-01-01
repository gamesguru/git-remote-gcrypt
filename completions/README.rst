======================================
Shell Completion for git-remote-gcrypt
======================================

This directory contains shell completion scripts for ``git-remote-gcrypt``.

Installation
============

Bash
----

System-wide (requires sudo)::

    sudo cp completions/bash/git-remote-gcrypt /etc/bash_completion.d/

User-only::

    mkdir -p ~/.local/share/bash-completion/completions
    cp completions/bash/git-remote-gcrypt ~/.local/share/bash-completion/completions/

Zsh
---

System-wide (requires sudo)::

    sudo cp completions/zsh/_git-remote-gcrypt /usr/share/zsh/site-functions/

User-only::

    mkdir -p ~/.zsh/completions
    cp completions/zsh/_git-remote-gcrypt ~/.zsh/completions/
    # Add to ~/.zshrc: fpath=(~/.zsh/completions $fpath)

Fish
----

User-only (Fish doesn't have system-wide completions)::

    mkdir -p ~/.config/fish/completions
    cp completions/fish/git-remote-gcrypt.fish ~/.config/fish/completions/

Supported Completions
=====================

- ``-h``, ``--help`` - Show help message
- ``-v``, ``--version`` - Show version information
- ``--check`` - Check if URL is a gcrypt repository

Notes
=====

- Completions are optional and not required for normal operation
- ``git-remote-gcrypt`` is typically invoked by git automatically
- These completions are useful for manual invocation and testing

