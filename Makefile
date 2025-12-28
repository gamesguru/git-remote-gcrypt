SHELL:=/bin/bash
.DEFAULT_GOAL := _help

# NOTE: must put a <TAB> character and two pound with an "H",
#       i.e., "\t##H" to show up in this list.  Keep it brief! IGNORE_ME
.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'

# Absolute path to avoid LD_PRELOAD errors
PWD := $(shell pwd)
# Output directories inside .coverage/
COV_ROOT    := $(PWD)/.coverage
COV_INSTALL := $(COV_ROOT)/installer
COV_SYSTEM  := $(COV_ROOT)/system

.PHONY: coverage
coverage: coverage-install coverage-system	##H Run full coverage suite (Installer + System)
	@echo "📊 Full coverage suite complete."
	@echo "   Installer: file://$(COV_INSTALL)/index.html"
	@echo "   System:    file://$(COV_SYSTEM)/index.html"

.PHONY: coverage-install
coverage-install: check-deps	##H Run installer logic tests only
	@echo "🚀 [Installer] Preparing coverage..."
	@mkdir -p $(COV_INSTALL)
	@echo "🧪 Running kcov on install.sh..."
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=.git,tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh
	@echo "✅ [Installer] Done."

.PHONY: coverage-system
coverage-system: check-deps	##H Run core system tests (system-test.sh & multikey)
	@echo "🚀 [System] Preparing coverage..."
	@mkdir -p $(COV_SYSTEM)

	@# Run Main System Test
	@if [ -f "./tests/system-test.sh" ]; then \
		echo "🧪 Running kcov on system-test.sh..."; \
		chmod +x ./tests/system-test.sh; \
		kcov --bash-handle-sh-invocation \
		     --include-pattern=git-remote-gcrypt \
		     --exclude-path=.git,tests \
		     $(COV_SYSTEM) \
		     ./tests/system-test.sh; \
	else \
		echo "⚠️  [System] ./tests/system-test.sh not found."; \
	fi

	@# Run Multikey System Test
	@if [ -f "./tests/system-test-multikey.sh" ]; then \
		echo "🧪 Running kcov on system-test-multikey.sh..."; \
		chmod +x ./tests/system-test-multikey.sh; \
		kcov --bash-handle-sh-invocation \
		     --include-pattern=git-remote-gcrypt \
		     --exclude-path=.git,tests \
		     $(COV_SYSTEM) \
		     ./tests/system-test-multikey.sh; \
	fi
	@echo "✅ [System] Done."

.PHONY: check-deps
check-deps:	##H Verify kcov and rst2man are installed
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }
	@command -v rst2man >/dev/null 2>&1 || command -v rst2man.py >/dev/null 2>&1 || { \
		echo "⚠️  Warning: 'rst2man' is missing. You won't hit 100% on installer tests."; \
	}

.PHONY: install-deps
install-deps:	##H Install dependencies (Ubuntu/Debian)
	sudo apt-get update
	sudo apt-get install -y kcov python3-docutils

.PHONY: open
open:	##H Open the HTML reports in browser
	@echo "Opening reports..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		[ -f $(COV_INSTALL)/index.html ] && open $(COV_INSTALL)/index.html; \
		[ -f $(COV_SYSTEM)/index.html ] && open $(COV_SYSTEM)/index.html; \
	elif [ -n "$$WSL_DISTRO_NAME" ]; then \
		[ -f $(COV_INSTALL)/index.html ] && explorer.exe `wslpath -w $(COV_INSTALL)/index.html`; \
		[ -f $(COV_SYSTEM)/index.html ] && explorer.exe `wslpath -w $(COV_SYSTEM)/index.html`; \
	else \
		[ -f $(COV_INSTALL)/index.html ] && xdg-open $(COV_INSTALL)/index.html; \
		[ -f $(COV_SYSTEM)/index.html ] && xdg-open $(COV_SYSTEM)/index.html; \
	fi

.PHONY: clean
clean:	##H Remove .coverage artifacts
	rm -rf .coverage
