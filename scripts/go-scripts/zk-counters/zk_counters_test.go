package main

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"
)

const preDeployedAddr = ""

func TestZkCounters(t *testing.T) {
	if preDeployedAddr == "" {
		err := deploySC()
		NoError(t, err)
	}
	if k := os.Getenv("KURTOSIS_ENCLAVE"); k != "cdk" {
		t.Errorf("KURTOSIS_ENCLAVE expected to be 'cdk' but found '%s'", k)
	}
}

func deploySC() error {
	return nil
}

func NoError(t *testing.T, err error) {
	if err != nil {
		if t == nil {
			panic(err)
		} else {
			require.NoError(t, err)
		}
	}
}
