SHELL:=/bin/bash
.DEFAULT_GOAL=_help


.PHONY: test
test: clean
# 	kcov --include-path=./git-remote-gcrypt --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
# 		.kcov/ ./tests/system-test.sh
	kcov --include-path=./git-remote-gcrypt --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
		.kcov ./tests/system-test-multikey.sh
# 	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
# 		.kcov ./tests/system-test.sh
# 	kcov --include-path=$(pwd) --exclude-path=$(pwd)/.git,$(pwd)/debian,$(pwd)/tests \
# 		--merge .kcov ./tests/system-test-multikey.sh


.PHONY: clean
clean:
	rm -rf .kcov/*


ttt:
# 	rm -rf .kcov/*
# 	# Run 1
# 	kcov --include-path=$(shell pwd) \
# 	     --exclude-path=$(shell pwd)/.git,$(shell pwd)/debian,$(shell pwd)/tests \
# 	     .kcov ./tests/system-test.sh
# 	# Run 2 (Merge)
# 	kcov --include-path=$(shell pwd) \
# 	     --exclude-path=$(shell pwd)/.git,$(shell pwd)/debian,$(shell pwd)/tests \
# 	     --merge .kcov ./tests/system-test-multikey.sh
	kcov --include-path=/home/shane/repos/git-remote-gcrypt \
	     --exclude-path=/home/shane/repos/git-remote-gcrypt/.git,/home/shane/repos/git-remote-gcrypt/debian,/home/shane/repos/git-remote-gcrypt/tests \
	     --merge \
	     .kcov \
	     ./tests/system-test-multikey.sh
