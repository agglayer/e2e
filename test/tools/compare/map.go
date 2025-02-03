package compare

import (
	"encoding/json"
	"reflect"
)

// MapKeyComparisonResult provides detailed information about map key comparison
type MapKeyComparisonResult struct {
	Key       any
	Error     error
	InnerKeys []MapKeyComparisonResult
}

// MapComparisonResult provides detailed information about map comparison
type MapComparisonResult struct {
	// MismatchingKeys list all the keys that doesn't match with the reason why
	MismatchingKeys []MapKeyComparisonResult
}

// CollectionMismatchResult provides more details when there is a mismatch between collections
type CollectionMismatchResult struct {
	Size     int
	Elements any
}

// Maps provides a way to compare maps without taking care about its context, just metadata.
func Maps[tKey comparable, tValue any](srcMap, targetMap map[tKey]tValue) (*MapComparisonResult, error) {
	result := &MapComparisonResult{
		MismatchingKeys: []MapKeyComparisonResult{},
	}
	if srcMap == nil && targetMap == nil {
		return result, nil
	}

	if srcMap == nil {
		return nil, ErrMapCompareSourceMapIsNil
	} else if targetMap == nil {
		return nil, ErrMapCompareTargetMapIsNil
	}

	for srcKey, srcValue := range srcMap {
		targetValue, found := targetMap[srcKey]
		if !found {
			result.MismatchingKeys = append(result.MismatchingKeys, MapKeyComparisonResult{
				Key:   srcKey,
				Error: ErrMapCompareMissingKey,
			})
			continue
		}
		rSrcValue := reflect.ValueOf(srcValue)
		rTargetValue := reflect.ValueOf(targetValue)

		mkr := compareValues(rSrcValue, rTargetValue, srcKey)
		if mkr.Error != nil {
			result.MismatchingKeys = append(result.MismatchingKeys, mkr)
			continue
		}
	}

	for targetKey := range targetMap {
		if _, found := srcMap[targetKey]; !found {
			result.MismatchingKeys = append(result.MismatchingKeys, MapKeyComparisonResult{
				Key:   targetKey,
				Error: ErrMapCompareExtraKey,
			})
			continue
		}
	}
	// reflect.DeepEqual()
	return result, nil
}

// compareValues compare reflected values derived from the maps via the key
func compareValues[tKey comparable](srcValue, targetValue reflect.Value, key tKey) MapKeyComparisonResult {
	mkr := MapKeyComparisonResult{
		Key:       key,
		InnerKeys: []MapKeyComparisonResult{},
		Error:     nil,
	}
	if srcValue.Kind() != targetValue.Kind() {
		var src any = nil
		var target any = nil

		if srcValue.Kind() != reflect.Invalid {
			src = srcValue.Interface()
		}

		if targetValue.Kind() != reflect.Invalid {
			target = targetValue.Interface()
		}

		mkr.Error = NewValueCompareErr(ErrMapCompareKindMismatch, src, target)
		return mkr
	}

	if srcValue.Kind() == reflect.Invalid {
		return mkr
	}

	// type check
	if srcValue.Type() != targetValue.Type() {
		mkr.Error = NewValueCompareErr(ErrMapCompareTypeMismatch, srcValue.Type(), targetValue.Type())
		return mkr
	}

	// nil check
	switch srcValue.Kind() {
	case reflect.Map, reflect.Slice, reflect.Interface, reflect.Func:
		if srcValue.IsNil() != targetValue.IsNil() {
			return mkr
		}
	}

	// unsafe pointer check
	switch srcValue.Kind() {
	case reflect.Map, reflect.Slice, reflect.Pointer:
		if srcValue.UnsafePointer() == targetValue.UnsafePointer() {
			return mkr
		}
	}

	// collection size check
	switch srcValue.Kind() {
	case reflect.Slice:
		if srcValue.Len() != targetValue.Len() {
			srcCollectionMismatchResult := CollectionMismatchResult{
				Size:     srcValue.Len(),
				Elements: srcValue.Interface(),
			}

			targetCollectionMismatchResult := CollectionMismatchResult{
				Size:     targetValue.Len(),
				Elements: targetValue.Interface(),
			}

			srcResult, _ := json.Marshal(srcCollectionMismatchResult)
			targetResult, _ := json.Marshal(targetCollectionMismatchResult)

			mkr.Error = NewValueCompareErr(ErrMapCompareSliceSizeMismatch, string(srcResult), string(targetResult))
			return mkr
		}
	}

	// value check
	switch srcValue.Kind() {
	case reflect.Array:
		mismatch := false
		for i := 0; i < srcValue.Len(); i++ {
			innerMapKeyComparisonResult := compareValues(srcValue.Index(i), targetValue.Index(i), i)
			if innerMapKeyComparisonResult.Error != nil {
				mkr.InnerKeys = append(mkr.InnerKeys, innerMapKeyComparisonResult)
				mismatch = true
			}
		}
		if mismatch {
			mkr.Error = NewValueCompareErr(ErrMapCompareInnerKeyMismatch, nil, nil)
		}
		return mkr
	case reflect.Slice:
		// Special case for []byte, which is common.
		if srcValue.Type().Elem().Kind() == reflect.Uint8 {
			if !reflect.DeepEqual(srcValue.Bytes(), targetValue.Bytes()) {
				mkr.InnerKeys = append(mkr.InnerKeys, MapKeyComparisonResult{
					Key:   key,
					Error: ErrMapCompareByteSliceMismatch,
				})
			}
			return mkr
		}
		mismatch := false
		for i := 0; i < srcValue.Len(); i++ {
			innerMapKeyComparisonResult := compareValues(srcValue.Index(i), targetValue.Index(i), i)
			if innerMapKeyComparisonResult.Error != nil {
				mkr.InnerKeys = append(mkr.InnerKeys, innerMapKeyComparisonResult)
				mismatch = true
			}
		}
		if mismatch {
			mkr.Error = NewValueCompareErr(ErrMapCompareInnerKeyMismatch, nil, nil)
		}
		return mkr
	case reflect.Struct:
		mismatch := false
		for i, n := 0, srcValue.NumField(); i < n; i++ {
			innerMapKeyComparisonResult := compareValues(srcValue.Field(i), targetValue.Field(i), srcValue.Type().Field(i).Name)
			if innerMapKeyComparisonResult.Error != nil {
				mkr.InnerKeys = append(mkr.InnerKeys, innerMapKeyComparisonResult)
				mismatch = true
			}
		}
		if mismatch {
			mkr.Error = NewValueCompareErr(ErrMapCompareInnerKeyMismatch, nil, nil)
		}
		return mkr
	case reflect.Map:
		iter := srcValue.MapRange()
		mismatch := false
		for iter.Next() {
			val1 := iter.Value()
			val2 := targetValue.MapIndex(iter.Key())
			if val2.Kind() == reflect.Invalid {
				mkr.InnerKeys = append(mkr.InnerKeys, MapKeyComparisonResult{
					Key:   iter.Key().Interface(),
					Error: ErrMapCompareMissingKey,
				})
				mismatch = true
			} else {
				innerMapKeyComparisonResult := compareValues(val1, val2, reflect.ValueOf(iter.Key()))
				if innerMapKeyComparisonResult.Error != nil {
					mkr.InnerKeys = append(mkr.InnerKeys, innerMapKeyComparisonResult)
					mismatch = true
				}
			}
		}

		iter = targetValue.MapRange()
		for iter.Next() {
			val := srcValue.MapIndex(iter.Key())
			if val.Kind() == reflect.Invalid {
				mkr.InnerKeys = append(mkr.InnerKeys, MapKeyComparisonResult{
					Key:   iter.Key().Interface(),
					Error: ErrMapCompareExtraKey,
				})
				mismatch = true
			}
		}

		if mismatch {
			mkr.Error = NewValueCompareErr(ErrMapCompareInnerKeyMismatch, nil, nil)
		}
		return mkr
	case reflect.Interface, reflect.Pointer:
		return compareValues(srcValue.Elem(), targetValue.Elem(), key)
	case reflect.Func:
		return mkr
	case reflect.Int, reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64:
		if srcValue.Int() != targetValue.Int() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Int(), targetValue.Int())
		}
		return mkr
	case reflect.Uint, reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uintptr:
		if srcValue.Uint() != targetValue.Uint() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Uint(), targetValue.Uint())
		}
		return mkr
	case reflect.String:
		if srcValue.String() != targetValue.String() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.String(), targetValue.String())
		}
		return mkr
	case reflect.Bool:
		if srcValue.Bool() != targetValue.Bool() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Bool(), targetValue.Bool())
		}
		return mkr
	case reflect.Float32, reflect.Float64:
		if srcValue.Float() != targetValue.Float() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Float(), targetValue.Float())
		}
		return mkr
	case reflect.Complex64, reflect.Complex128:
		if srcValue.Complex() != targetValue.Complex() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Complex(), targetValue.Complex())
		}
		return mkr
	default:
		// Normal equality suffices
		if srcValue.Interface() == targetValue.Interface() {
			mkr.Error = NewValueCompareErr(ErrMapCompareValueMismatch, srcValue.Interface(), targetValue.Interface())
		}
		return mkr
	}
}
