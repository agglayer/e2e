This is a simple test scenario that's meant to serve as an
example. The test will spin up an enclave, delete the data directory
for CDK Erigon, then restart the service. After the service resumes,
we want to ensure that the service is able to resync and follow the
sequencer again.

