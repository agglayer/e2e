package compare

import (
	"errors"
	"fmt"
)

var (
	ErrMapCompareTypeMismatch      = errors.New("type mismatch")
	ErrMapCompareKindMismatch      = errors.New("kind mismatch")
	ErrMapCompareValueMismatch     = errors.New("value mismatch")
	ErrMapCompareSliceSizeMismatch = errors.New("slice size mismatch")
	ErrMapCompareByteSliceMismatch = errors.New("byte slice mismatch")
	ErrMapCompareSourceMapIsNil    = errors.New("source map is nil")
	ErrMapCompareTargetMapIsNil    = errors.New("target map is nil")
	ErrMapCompareInnerKeyMismatch  = errors.New("inner key mismatch")
	ErrMapCompareMissingKey        = errors.New("this key is missing in the target map")
	ErrMapCompareExtraKey          = errors.New("this key doesn't exist in the source map but exist in the target map")
)

type ValueCompareErr struct {
	Err      error
	Expected any
	Found    any
}

func NewValueCompareErr(err error, expected any, found any) ValueCompareErr {
	return ValueCompareErr{
		Err:      err,
		Expected: expected,
		Found:    found,
	}
}

func (e ValueCompareErr) Error() string {
	msg := fmt.Sprintf("error: %v", e.Err)
	if e.Expected != nil || e.Found != nil {
		msg += fmt.Sprintf(", expected: %v, found: %v", e.Expected, e.Found)
	}
	return msg
}
