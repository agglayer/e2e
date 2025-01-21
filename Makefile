.PHONY: test-bats
test-bats:
	@if [ "$$(uname)" = "Darwin" ]; then \
	    echo "Detected macOS, using macOS sed syntax"; \
	    sed -i "" "s|BATS_LIB_PATH=.*|BATS_LIB_PATH=\"$(PWD)/scripts/bats-scripts/lib\"|" .env; \
	else \
	    echo "Detected Linux, using Linux sed syntax"; \
	    sed -i "s|BATS_LIB_PATH=.*|BATS_LIB_PATH=\"$(pwd)/scripts/bats-scripts/lib\"|" .env; \
	fi; \
	echo "Sourcing .env and running bats tests"; \
	set -a; . $(PWD)/.env; set +a; \
	cd scripts/bats-scripts; bats -p batch-verifier.bats; \
	bats -p eoa-tx.bats

.PHONY: test-go
test-go:
	cd scripts/go-scripts; godotenv -f ../../.env go test -v ./...
	
.PHONY: install-go-dot-env
install-go-dot-env:
	go install github.com/joho/godotenv/cmd/godotenv@latest
	
.PHONY: install-bats-deps
install-bats-deps:
	# Install bats-core
	@if ! command -v bats &> /dev/null; then \
		git clone https://github.com/bats-core/bats-core.git /tmp/bats-core && \
		/tmp/bats-core/install.sh /usr/local; \
	else \
		echo "bats is already installed"; \
	fi
	
	# Install cast from Foundry
	@if ! command -v cast &> /dev/null; then \
		curl -L https://foundry.paradigm.xyz | bash && \
		~/.foundry/bin/foundryup; \
	else \
		echo "cast is already installed"; \
	fi

## Help display.
## Pulls comments from beside commands and prints a nicely formatted
## display with the commands and their usage information.
.DEFAULT_GOAL := help

.PHONY: help
help: ## Prints this help
	@grep -h -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	| sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-30s\033[0m %s\n", $$1, $$2}'