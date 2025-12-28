.ONESHELL:
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
cov-sys: check-deps	##H Run all system tests (Standard, Multi-key, Failures)
	@echo "🚀 [System] Preparing coverage..."
	@rm -rf $(COV_SYSTEM)
	@mkdir -p $(COV_SYSTEM)

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
	@echo "👉 Run 'make missed' to see which lines are not covered."

.PHONY: missed
missed:	##H Show missing/uncovered lines
	@echo "🔍 Analyzing coverage for git-remote-gcrypt..."
	@XML_FILE=$$(find $(COV_SYSTEM) -name "cobertura.xml" | grep "merged" | head -n 1); \
	[ -z "$$XML_FILE" ] && XML_FILE=$$(find $(COV_SYSTEM) -name "cobertura.xml" | head -n 1); \
	if [ -f "$$XML_FILE" ]; then \
		echo "📄 Using data from: $$XML_FILE"; \
		python3 -c "import xml.etree.ElementTree as E, textwrap; \
		m = [l.get('number') for c in E.parse('$$XML_FILE').findall('.//class') if 'git-remote-gcrypt' in c.get('filename') for l in c.findall('.//line') if l.get('hits') == '0']; \
		print(f'\n❌ \033[1m{len(m)} MISSING LINES\033[0m:'); \
		print(textwrap.fill(', '.join(m), width=72, initial_indent='  ', subsequent_indent='  '))"; \
	else \
		echo "❌ Error: 'cobertura.xml' not found."; \
	fi

.PHONY: cov-inst
cov-inst: check-deps	##H Run installer logic tests
	@echo "🚀 [Installer] Preparing coverage..."
	@rm -rf $(COV_INSTALL)
	@mkdir -p $(COV_INSTALL)
	@kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=$(PWD)/.git,$(PWD)/tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh
	@echo "✅ [Installer] Done. Report: file://$(COV_INSTALL)/index.html"

.PHONY: open
open:	##H Open the coverage report in browser
	@if [ -f "$(COV_SYSTEM)/index.html" ]; then \
		xdg-open "$(COV_SYSTEM)/index.html" 2>/dev/null || open "$(COV_SYSTEM)/index.html"; \
	fi

.PHONY: check-deps
check-deps:	##H Check for kcov
	@command -v kcov >/dev/null 2>&1 || { echo "❌ Error: 'kcov' is not installed."; exit 1; }

.PHONY: clean
clean: ##H Clean artifacts
	rm -rf .coverage
