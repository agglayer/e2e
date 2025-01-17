.PHONY: compile-sc
compile-sc:
	docker run --rm --platform=linux/amd64 -v .:/contracts ethereum/solc:0.8.20-alpine - /contracts/zk_counters.sol -o /contracts/ --abi --bin --overwrite --optimize
	docker run --rm --platform=linux/amd64 -v .:/contracts ethereum/client-go:alltools-latest abigen --bin /contracts/ZkCounters.bin --abi /contracts/ZkCounters.abi --pkg main --out /contracts/zk_counters_sc.go
	sleep 1
	rm ./ZkCounters.bin ./ZkCounters.abi