SHELL:=/bin/bash
.DEFAULT_GOAL := _help

# NOTE: must put a <TAB> character and two pound with an "H",
#       i.e., "\t##H" to show up in this list.  Keep it brief! IGNORE_ME
.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@grep -h "##H" $(MAKEFILE_LIST) | grep -v IGNORE_ME | sed -e 's/##H//' | column -t -s $$'\t'


# Absolute path needed for kcov
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_INSTALL := $(COV_ROOT)/installer
COV_SYSTEM  := $(COV_ROOT)/system

.PHONY: cov
cov: cov-inst cov-sys	##H Run full coverage suite
	@echo "📊 Full coverage suite complete."
	@echo "   Installer: file://$(COV_INSTALL)/index.html"
	@echo "   System:    file://$(COV_SYSTEM)/index.html"

.PHONY: cov-inst
cov-inst: check-deps	##H Run installer logic tests
	@echo "🚀 [Installer] Preparing coverage..."
	@mkdir -p $(COV_INSTALL)
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=.git,tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh
	@echo "✅ [Installer] Done."

.PHONY: cov-sys
cov-sys: check-deps	##H Run core system tests (system-*.sh)
	@echo "🚀 [System] Preparing coverage..."
	@mkdir -p $(COV_SYSTEM)

	@# 1. Main System Test
	@if [ -f "./tests/system-test.sh" ]; then \
		echo "🧪 Running kcov on system-test.sh..."; \
		kcov --include-path=$(PWD)/git-remote-gcrypt \
		     $(COV_SYSTEM) \
		     ./tests/system-test.sh; \
	fi

	@# 2. Multikey System Test
	@if [ -f "./tests/system-test-multikey.sh" ]; then \
		echo "🧪 Running kcov on system-test-multikey.sh..."; \
		kcov --include-path=$(PWD)/git-remote-gcrypt \
		     $(COV_SYSTEM) \
		     ./tests/system-test-multikey.sh; \
	fi
	@echo "✅ [System] Done."

.PHONY: check-deps
check-deps:	##H Check for kcov/rst2man
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }
	@command -v rst2man >/dev/null 2>&1 || command -v rst2man.py >/dev/null 2>&1 || { \
		echo "⚠️  Warning: 'rst2man' is missing (install python3-docutils)."; \
	}

.PHONY: clean
clean:	##H Clean artifacts
	rm -rf .coverage
