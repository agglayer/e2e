.PHONY: check-dependencies compile-contracts

check-dependencies:
	./scripts/check-dependencies.sh

compile-contracts:
	find core/contracts/ -type f | grep -E '(yul|sol)' | while read contract; do echo "$$contract"; forge build -C "$$contract" ; done
	./core/helpers/scripts/postprocess_contracts.sh

