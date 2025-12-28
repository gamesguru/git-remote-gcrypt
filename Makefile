SHELL:=/bin/bash
.DEFAULT_GOAL := _help

# -- Config --
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_SYSTEM  := $(COV_ROOT)/system
COV_INSTALL := $(COV_ROOT)/installer

.PHONY: _help
_help:
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'

.PHONY: cov-sys
cov-sys: check-deps	##H Run system tests (Main logic & Multi-key)
	@echo "🚀 [System] Preparing coverage..."
	@rm -rf $(COV_SYSTEM)
	@mkdir -p $(COV_SYSTEM)

	@# 1. GPG_TTY: Tells GPG "I have a terminal" (prevents basic hangs).
	@# 2. GIT_CONFIG_PARAMETERS: Injects '--pinentry-mode loopback' via Git config.
	@#    This fixes the Step 5 hang by making GPG fail fast on missing keys.
	@export GPG_TTY=$$(tty); \
	 export GIT_CONFIG_PARAMETERS="'gcrypt.gpg-args=--pinentry-mode loopback --no-tty'"; \
	 for test_script in tests/system-test*.sh; do \
	     echo "🧪 Running $$test_script..."; \
	     kcov --include-path=$(PWD) \
	          --include-pattern=git-remote-gcrypt \
	          --exclude-path=$(PWD)/.git,$(PWD)/tests \
	          $(COV_SYSTEM) \
	          ./$$test_script || echo "⚠️  $$test_script returned error (likely expected)"; \
	 done

	@echo "✅ [System] Done. Report: file://$(COV_SYSTEM)/index.html"

.PHONY: cov-inst
cov-inst: check-deps	##H Run installer logic tests
	@echo "🚀 [Installer] Preparing coverage..."
	@rm -rf $(COV_INSTALL)
	@mkdir -p $(COV_INSTALL)

	@echo "🧪 Running test-install-logic.sh..."
	@# We use --bash-handle-sh-invocation here because install.sh might still be /bin/sh
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=$(PWD)/.git,$(PWD)/tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh

	@echo "✅ [Installer] Done. Report: file://$(COV_INSTALL)/index.html"

.PHONY: open
open:	##H Open the coverage report (System by default)
	@# Tries System first, then Installer
	@if [ -f "$(COV_SYSTEM)/index.html" ]; then \
		xdg-open "$(COV_SYSTEM)/index.html" 2>/dev/null || open "$(COV_SYSTEM)/index.html"; \
	elif [ -f "$(COV_INSTALL)/index.html" ]; then \
		xdg-open "$(COV_INSTALL)/index.html" 2>/dev/null || open "$(COV_INSTALL)/index.html"; \
	else \
		echo "❌ No reports found. Run 'make cov-sys' or 'make cov-inst' first."; \
	fi

.PHONY: check-deps
check-deps:	##H Check for kcov
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }

.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
