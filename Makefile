<<<<<<< Updated upstream
.PHONY: install uninstall check-dependencies compile-contracts
=======
.PHONY: install uninstall install-runner install-dependencies
>>>>>>> Stashed changes

install-runner:
	mkdir -p ~/.local/bin
	cp test-runner.sh ~/.local/bin/polygon-test-runner
	chmod +x ~/.local/bin/polygon-test-runner
	# Auto-add ~/.local/bin to PATH if not present
	if ! echo "$$PATH" | grep -q "$$HOME/.local/bin"; then \
		echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> $$HOME/.bashrc; \
		echo 'export PATH="$$HOME/.local/bin:$$PATH"' >> $$HOME/.zshrc; \
		echo "✅ Installed! Added ~/.local/bin to PATH."; \
	fi
	# Apply change immediately for the current shell session
	export PATH="$$HOME/.local/bin:$$PATH"
	echo "🔄 Reloading PATH for this session..."
	exec $$SHELL

install:
	# Install runner
	$(MAKE) install-runner

	# Check core dependencies
	$(MAKE) check-dependencies

check-dependencies:
	@echo "🔍 Checking required dependencies..."

	# Check for yq
	if ! command -v yq &> /dev/null; then \
		echo "⚠️  WARNING: 'yq' not found. Install with: pip3 install yq"; \
	else \
		echo "✅ yq is installed."; \
	fi

	# Check for polycli
	if ! command -v polycli &> /dev/null; then \
		echo "⚠️  WARNING: 'polycli' not found. Install manually from: https://github.com/0xPolygon/polygon-cli"; \
	else \
		echo "✅ polycli is installed."; \
	fi

	# Check for Foundry
	if ! command -v foundryup &> /dev/null; then \
		echo "⚠️  WARNING: 'Foundry' not found. Install with: curl -L https://foundry.paradigm.xyz | bash"; \
	else \
		echo "✅ Foundry is installed."; \
	fi

	# Check for Go
	if ! command -v go &> /dev/null; then \
		echo "⚠️  WARNING: 'Go' not found. Install from: https://golang.org/dl/"; \
	else \
		echo "✅ Go is installed."; \
	fi

	@echo "🔍 Dependency check complete."

uninstall:
	rm -f ~/.local/bin/polygon-test-runner
	echo "❌ Uninstalled polygon-test-runner."

compile-contracts:
	forge build
	./scripts/postprocess-contracts.sh
