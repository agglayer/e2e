.PHONY: check-dependencies compile-contracts update-tests-inventory

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

