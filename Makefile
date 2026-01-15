SHELL:=/bin/bash
# .ONESHELL:
# .EXPORT_ALL_VARIABLES:
.DEFAULT_GOAL := _help
.SHELLFLAGS = -ec

.PHONY: _help
_help:
	@printf "\nUsage: make <command>, valid commands:\n\n"
	@awk 'BEGIN {FS = ":.*?##H "}; \
		/##H/ && !/@awk.*?##H/ { \
			target=$$1; doc=$$2; \
			if (length(target) > max) max = length(target); \
			targets[NR] = target; docs[NR] = doc; list[NR] = 1; \
		} \
		END { \
			for (i = 1; i <= NR; i++) { \
				if (list[i]) printf "  \033[1;34m%-*s\033[0m  %s\n", max, targets[i], docs[i]; \
			} \
			print ""; \
		}' $(MAKEFILE_LIST)

.PHONY: vars
vars:	##H Display all Makefile variables (simple)
	$(info === Makefile Variables (file/command/line origin) ===)
	@$(foreach V,$(sort $(.VARIABLES)), \
		$(if $(filter file command line,$(origin $(V))), \
			$(info $(shell printf "%-30s" "$(V)") = $(value $(V))) \
		) \
	)


define print_err
printf "\033[1;31m%s\033[0m\n" "$(1)"
endef

define print_warn
printf "\033[1;33m%s\033[0m\n" "$(1)"
endef

define print_success
printf "\033[1;34m✓ %s\033[0m\n" "$(1)"
endef


define print_info
printf "\033[1;36m%s\033[0m\n" "$(1)"
endef

define print_target
printf "\033[1;35m-> %s\033[0m\n" "$(1)"
endef


.PHONY: check/deps
check/deps:	##H Verify kcov & shellcheck
	@$(call print_info,  --- shellcheck version ---)
	@shellcheck --version
	@$(call print_info,  --- kcov version ---)
	@kcov --version



LINT_LOCS_PY ?= $(shell git ls-files '*.py')
LINT_LOCS_SH ?= $(shell git ls-files '*.sh' ':!tests/system-test.sh')

.PHONY: format
format:	##H Format scripts
	@$(call print_target,format)
	@$(call print_info,Formatting shell scripts...)
	shfmt -ci -bn -s -w $(LINT_LOCS_SH)
	@$(call print_success,OK.)
	@$(call print_info,Formatting Python scripts...)
	-black $(LINT_LOCS_PY)
	-isort $(LINT_LOCS_PY)
	@$(call print_success,OK.)

.PHONY: lint
lint:	##H Run shellcheck
	@$(call print_target,lint)
	@$(call print_info,Running shellcheck...)
	shellcheck --version
	shellcheck install.sh
	shellcheck -s sh -e SC3043,SC2001 git-remote-gcrypt
	shellcheck tests/*.sh
	@$(call print_success,OK.)
	@$(call print_info,Linting Python scripts...)
	-ruff check $(LINT_LOCS_PY)
	@$(call print_success,OK.)


# --- Test Config ---
PWD := $(shell pwd)
COV_ROOT    := $(PWD)/.coverage
COV_SYSTEM  := $(COV_ROOT)/system
COV_INSTALL := $(COV_ROOT)/installer

.PHONY: test/, test
test: test/
test/:	##H Run tests (purity checks only if kcov missing)
	@if command -v kcov >/dev/null 2>&1; then \
		$(MAKE) test/installer test/system test/cov; \
	else \
		$(call print_warn,kcov not found: skipping coverage/bash tests.); \
		$(MAKE) test/purity; \
	fi

.PHONY: test/installer
test/installer:	##H Test installer logic
	@rm -rf $(COV_INSTALL)
	@mkdir -p $(COV_INSTALL)
	@export COV_DIR=$(COV_INSTALL); \
	 kcov --bash-handle-sh-invocation \
	     --include-pattern=install.sh \
	     --exclude-path=$(PWD)/.git,$(PWD)/tests \
	     $(COV_INSTALL) \
	     ./tests/test-install-logic.sh


.PHONY: test/purity
test/purity: check/deps/shellcheck	##H Run logic tests (with native /bin/sh)
	@echo "running system tests (native /bin/sh)..."
	@export GPG_TTY=$$(tty); \
	 [ -n "$(DEBUG)$(V)" ] && export GCRYPT_DEBUG=1; \
	 export GIT_CONFIG_PARAMETERS="'gcrypt.gpg-args=--pinentry-mode loopback --no-tty'"; \
	 for test_script in tests/system-test*.sh; do \
	     ./$$test_script || exit 1; \
	 done

.PHONY: test/system
test/system:	##H Run logic tests (with bash & coverage)
	@echo "running system tests (coverage/bash)..."
	@rm -rf $(COV_SYSTEM)
	@mkdir -p $(COV_SYSTEM)
	@export GPG_TTY=$$(tty); \
	 [ -n "$(DEBUG)$(V)" ] && export GCRYPT_DEBUG=1 && $(call print_warn,Debug mode enabled); \
	 export GIT_CONFIG_PARAMETERS="'gcrypt.gpg-args=--pinentry-mode loopback --no-tty'"; \
	 sed -i 's|^#!/bin/sh|#!/bin/bash|' git-remote-gcrypt; \
	 trap "sed -i 's|^#!/bin/bash|#!/bin/sh|' git-remote-gcrypt" EXIT; \
	 for test_script in tests/system-test*.sh; do \
	     kcov --include-path=$(PWD) \
	          --include-pattern=git-remote-gcrypt \
	          --exclude-path=$(PWD)/.git,$(PWD)/tests \
	          $(COV_SYSTEM) \
	          ./$$test_script; \
	 done; \
	 sed -i 's|^#!/bin/bash|#!/bin/sh|' git-remote-gcrypt; \
	 trap - EXIT


# Find coverage XML: preference for "merged" > any other (search depth: 2 subdirs)
find_coverage_xml = $(or \
	$(filter %/merged/cobertura.xml, $(wildcard $(1)/cobertura.xml $(1)/*/cobertura.xml $(1)/*/*/cobertura.xml)), \
	$(firstword $(wildcard $(1)/cobertura.xml $(1)/*/cobertura.xml $(1)/*/*/cobertura.xml)) \
)

CHECK_COVERAGE = $(if $(call find_coverage_xml,$(1)), \
	echo "" ; \
	echo "Report for: file://$(abspath $(dir $(call find_coverage_xml,$(1))))/index.html" ; \
	XML_FILE="$(call find_coverage_xml,$(1))" PATT="$(2)" FAIL_UNDER="$(3)" python3 tests/coverage_report.py, \
	echo "" ; \
	echo "Error: No coverage report found for $(2) in $(1)" ; \
	exit 1)


.PHONY: test/cov _test_cov_internal
test/cov:	##H Show coverage gaps
	$(MAKE) _test_cov_internal

_test_cov_internal:
	@err=0; \
	$(call CHECK_COVERAGE,$(COV_SYSTEM),git-remote-gcrypt,59) || err=1; \
	$(call CHECK_COVERAGE,$(COV_INSTALL),install.sh,78) || err=1; \
	exit $$err



# Version from git describe (or fallback)
__VERSION__ := $(shell git describe --tags --always --dirty 2>/dev/null || echo "@@DEV_VERSION@@")


.PHONY: generate
generate:	##H Autogen man docs & shell completions
	@$(call print_info,Generating documentation and completions...)
	./utils/gen_docs.sh
	@$(call print_success,Generated.)


.PHONY: install/, install
install/: install
install:	##H Install system-wide
	@$(call print_target,install)
	@$(call print_info,Installing git-remote-gcrypt...)
	@bash ./install.sh
	@$(call print_success,Installed.)

.PHONY: install/user
install/user:	##H make install prefix=~/.local
	$(MAKE) install prefix=~/.local


.PHONY: check/install
check/install:	##H Verify installation works
	bash ./tests/verify-system-install.sh


.PHONY: uninstall/, uninstall
uninstall/: uninstall
uninstall:	##H Uninstall
	@$(call print_target,uninstall)
	@bash ./uninstall.sh
	@$(call print_success,Uninstalled.)

.PHONY: uninstall/user
uninstall/user:	##H make uninstall prefix=~/.local
	$(MAKE) uninstall prefix=~/.local




.PHONY: deploy/debian
deploy/debian:	##H Build Debian package
	@$(call print_target,deploy/debian)
	@$(call print_info,Building Debian package...)
	gbp buildpackage -uc -us
	@$(call print_success,Built Debian package.)

.PHONY: deploy/redhat
deploy/redhat:	##H Build RPM package
	@$(call print_target,deploy/redhat)
	@$(call print_info,Building RPM package...)
	rpmbuild -bb redhat/git-remote-gcrypt.spec
	@$(call print_success,Built RPM package.)

.PHONY: clean
clean:	##H Clean up
	rm -rf .coverage .build_tmp
