package compare

import (
	"fmt"
	"io"
)

type WriterReporter struct {
	w io.Writer
}

func NewWriterReporter(w io.Writer) *WriterReporter {
	return &WriterReporter{w: w}
}

func (r *WriterReporter) GenerateReport(result MapComparisonResult) {
	r.GenerateMismatchingKeysReport(result)
}

func (r *WriterReporter) GenerateMismatchingKeysReport(result MapComparisonResult) {
	r.generateComparisonCollectionReport("MISMATCHING KEYS", result.MismatchingKeys, true)
}

func (r *WriterReporter) writeLineSeparator() error {
	_, err := r.w.Write([]byte("-------------------------\n"))
	if err != nil {
		return err
	}
	return nil
}

func (r *WriterReporter) generateComparisonCollectionReport(title string, collection []MapKeyComparisonResult, writeOnlyWithError bool) error {
	if err := r.writeLineSeparator(); err != nil {
		return err
	}
	if _, err := r.w.Write([]byte(fmt.Sprintf("%v\n", title))); err != nil {
		return err
	}
	for _, item := range collection {
		if !writeOnlyWithError || (writeOnlyWithError && item.Error != nil) {
			r.writeMapKeyComparisonResult("", item, writeOnlyWithError)
		}
	}
	if err := r.writeLineSeparator(); err != nil {
		return err
	}
	return nil
}

func (r *WriterReporter) writeMapKeyComparisonResult(prefix string, result MapKeyComparisonResult, writeOnlyWithError bool) {
	keyName := ""
	if prefix == "" {
		keyName = fmt.Sprintf("%v", result.Key)
	} else {
		keyName = fmt.Sprintf("%v.%v", prefix, result.Key)
	}

	if result.Error != nil {
		r.w.Write([]byte(fmt.Sprintf("- key: %v, error: %v\n", keyName, result.Error)))
	} else {
		r.w.Write([]byte(fmt.Sprintf("- key: %v\n", keyName)))
	}

	for _, innerKey := range result.InnerKeys {
		if !writeOnlyWithError || (writeOnlyWithError && innerKey.Error != nil) {
			r.writeMapKeyComparisonResult(keyName, innerKey, writeOnlyWithError)
		}
	}
}
