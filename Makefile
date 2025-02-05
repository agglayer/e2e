.PHONY: install uninstall install-dependencies

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

	# Install core dependencies
	$(MAKE) install-dependencies

install-dependencies:
	@echo "🔧 Installing required dependencies..."

	# Install yq
	if ! command -v yq &> /dev/null; then \
		echo "📦 Installing yq..."; \
		pip3 install yq; \
	fi

	# Install polycli
	if ! command -v polycli &> /dev/null; then \
		echo "📦 Installing polycli..."; \
		POLYCLI_VERSION=$$(curl -s https://api.github.com/repos/0xPolygon/polygon-cli/releases/latest | jq -r '.tag_name'); \
		tmp_dir=$$(mktemp -d); \
		curl -L "https://github.com/0xPolygon/polygon-cli/releases/download/$${POLYCLI_VERSION}/polycli_$${POLYCLI_VERSION}_linux_amd64.tar.gz" | tar -xz -C "$$tmp_dir"; \
		mv "$$tmp_dir"/* /usr/local/bin/polycli; \
		rm -rf "$$tmp_dir"; \
		sudo chmod +x /usr/local/bin/polycli; \
		polycli version; \
	fi

	# Install Foundry
	if ! command -v foundryup &> /dev/null; then \
		echo "📦 Installing Foundry..."; \
		curl -L https://foundry.paradigm.xyz | bash; \
		source $$HOME/.bashrc || source $$HOME/.zshrc; \
		foundryup; \
	fi

	# Install Go
	if ! command -v go &> /dev/null; then \
		echo "📦 Installing Go..."; \
		wget https://golang.org/dl/go1.22.11.linux-amd64.tar.gz; \
		sudo tar -C /usr/local -xzf go1.22.11.linux-amd64.tar.gz; \
		rm go1.22.11.linux-amd64.tar.gz; \
		export PATH=$$PATH:/usr/local/go/bin; \
	fi

	@echo "✅ All dependencies installed!"

uninstall:
	rm -f ~/.local/bin/polygon-test-runner
	echo "❌ Uninstalled polygon-test-runner."
