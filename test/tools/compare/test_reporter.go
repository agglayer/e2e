package compare

import (
	"fmt"
	"testing"

	"github.com/agglayer/e2e/test/tools/log"
)

type TestReporter struct {
	t *testing.T
}

func NewTestReporter(t *testing.T) *TestReporter {
	return &TestReporter{t: t}
}

func (r *TestReporter) GenerateReport(result MapComparisonResult) {
	log.Msg(r.t, "")
	if len(result.MismatchingKeys) > 0 {
		log.Error(r.t, "-- ERROR: maps are not equal, there are mismatching fields:")
		for _, item := range result.MismatchingKeys {
			if item.Error != nil {
				r.writeMapKeyComparisonResult("", item)
			}
		}
	} else {
		log.Msg(r.t, "-- PASS: Maps are equal.")
	}
}

func (r *TestReporter) writeMapKeyComparisonResult(prefix string, result MapKeyComparisonResult) {
	keyName := ""
	if prefix == "" {
		keyName = fmt.Sprintf("%v", result.Key)
	} else {
		keyName = fmt.Sprintf("%v.%v", prefix, result.Key)
	}

	if result.Error != nil {
		log.LineBreaker(r.t)
		if err, ok := result.Error.(ValueCompareErr); ok {
			log.Msg(r.t, "     key:", keyName)
			log.Msg(r.t, "   error:", err.Err)
			// msg := fmt.Sprintf("\n     key: %v\n   error: %v", keyName, err.Err)
			if err.Expected != nil || err.Found != nil {
				log.Msg(r.t, "expected:", err.Expected)
				log.Msg(r.t, "   found:", err.Found)
				// msg += fmt.Sprintf("\nexpected: %v\n   found: %v", err.Expected, err.Found)
			}
			// log.Msg(r.t, msg)
		} else {
			log.Msg(r.t, "     key:", keyName)
			log.Msg(r.t, "   error:", result.Error)
		}
	} else {
		log.Msgf(r.t, "key: \"%v\"", keyName)
	}

	for _, innerKey := range result.InnerKeys {
		r.writeMapKeyComparisonResult(keyName, innerKey)
	}
}
