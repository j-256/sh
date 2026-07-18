# Makefile - task runner for the sh repo
# Needs only GNU Make + bash (both ship with macOS). The scripts have no
# runtime dependencies and there is no build step, so every target is a thin
# wrapper around tests/*.sh

# Absolute path to this Makefile's dir, so targets work from anywhere
# (e.g. make -C /path/to/repo test) -- mirrors how the scripts resolve paths
root := $(dir $(lastword $(MAKEFILE_LIST)))

.PHONY: help test setup uninstall

# Print the available targets (default target -- a bare `make` lands here)
help:
	@echo 'Usage:'
	@echo '  make test       run the full test suite'
	@echo '  make test ARGS="pin-dns tsd"   run named tests'
	@echo '  make setup      activate this repo'"'"'s git hooks'
	@echo '  make uninstall  deactivate the git hooks'

# Run the test suite; target specific scripts with: make test ARGS="pin-dns"
test:
	@/bin/bash $(root)tests/test-runner.sh $(ARGS)

# Activate this repo's tracked git hooks (points core.hooksPath at tests/hooks/)
setup:
	@/bin/bash $(root)tests/install-hooks.sh

# Deactivate the tracked git hooks (restore git's default hooks path)
uninstall:
	@/bin/bash $(root)tests/install-hooks.sh --uninstall
