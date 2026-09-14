# Makefile - task runner for the sh repo
# Shell utility verification needs only GNU Make + bash
# Browser capture dependencies live separately under tools/cover

# Absolute path to this Makefile's dir, so targets work from anywhere
# (e.g. make -C /path/to/repo test) -- mirrors how the scripts resolve paths
root := $(dir $(lastword $(MAKEFILE_LIST)))

.PHONY: help test setup uninstall

# Print the available targets (default target -- a bare `make` lands here)
help:
	@echo 'Usage:'
	@echo '  make test       run the full test suite'
	@echo '  make test ARGS="pin-dns tsd"   run named tests'
	@echo '  make capture-cover  capture the published Toolio catalog'
	@echo '  make setup      activate this repo'"'"'s git hooks'
	@echo '  make uninstall  deactivate the git hooks'

# Run the test suite; target specific scripts with: make test ARGS="pin-dns"
test:
	@/bin/bash $(root)test/test-runner.sh $(ARGS)

# Activate this repo's tracked git hooks (points core.hooksPath at test/hooks/)
setup:
	@/bin/bash $(root)test/install-hooks.sh

# Deactivate the tracked git hooks (restore git's default hooks path)
uninstall:
	@/bin/bash $(root)test/install-hooks.sh --uninstall

.PHONY: capture-cover
capture-cover:
	@npm --prefix $(root)tools/cover run capture -- $(ARGS)
