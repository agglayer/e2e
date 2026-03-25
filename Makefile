.PHONY: check-dependencies compile-contracts update-tests-inventory update-pos-compat-versions

check-dependencies:
	./scripts/check-dependencies.sh

compile-contracts:
	find core/contracts/ -type f -name '*.sol' | while read contract; do echo "$$contract"; forge build -C "$$contract" ; done
	# .yul files: use --root so forge picks up the per-directory foundry.toml which sets
	# lint_on_build = false. Solar (forge's linter) does not support Yul syntax.
	find core/contracts/ -type f -name '*.yul' | while read f; do dir=$$(dirname "$$f"); echo "$$f"; forge build --root "$$dir" ; done
	./core/helpers/scripts/postprocess_contracts.sh

## Run before opening a PR that touches test files.
## Updates TESTSINVENTORY.md and the test_tags section of README.md.
update-tests-inventory:
	./scripts/update-tests-inventory.sh

## Run before opening a PR that touches PoS-related files.
## Fetches the latest bor/erigon releases and updates scripts/pos-version-matrix/compat-versions.yml.
## Requires a GITHUB_TOKEN env var to avoid rate limits: GITHUB_TOKEN=<pat> make update-pos-compat-versions
update-pos-compat-versions:
	pip install -q -r scripts/pos-version-matrix/requirements.txt
	python3 scripts/pos-version-matrix/update-compat-versions.py

