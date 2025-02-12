package compare

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func Test_MapComparer(t *testing.T) {
	t.Skip()
	type item struct {
		a int
		b string
		c bool
		d []any
	}
	i1 := item{1, "a", true, []any{11, "aa", false}}
	i2 := item{2, "b", false, []any{22, "bb", true}}
	i3 := item{3, "c", true, []any{33, "cc", true}}
	m1 := map[string]interface{}{
		// "f1": 1,
		// "f2": "abc",
		// "f3": true,
		// "f4": []int{1, 2, 3},
		// "f5": []any{1, "", true},
		// "f6": []item{i1, i2, i3},
		"f7": []any{1, "", true, i1, i2, i3},
		// "f8": nil,
		// "f9": 1,
		// "f10": map[string]any{
		// 	// "f1": 11,
		// 	// "f2": map[string]any{
		// 	// 	"f1": 111,
		// 	// 	"f2": "a",
		// 	// 	"f3": map[string]any{
		// 	// 		"f1": 1111,
		// 	// 		"f2": "aa",
		// 	// 		"f3": true,
		// 	// 	},
		// 	// },
		// 	"f3": map[string]any{
		// 		"f1": map[string]any{
		// 			"f1": false,
		// 		},
		// 	},
		// 	"f5": map[string]any{
		// 		"f1": map[string]any{
		// 			"f1": false,
		// 			"f2": []any{1, "", true},
		// 		},
		// 	},
		// },
	}
	m2 := map[string]interface{}{
		// "f1": 2,
		// "f2": "abcd",
		// "f3": false,
		// "f4": []int{3, 2, 1},
		// "f5": []any{true, "", 1, ""},
		// "f6": []item{i1, i2, i3},
		"f7": []any{1, "", true, i3, i1, i2},
		// "f8": nil,
		// "f10": map[string]any{
		// 	// "f1": 11,
		// 	// "f2": map[string]any{
		// 	// 	"f1": 111,
		// 	// 	"f2": "b",
		// 	// 	"f3": map[string]any{
		// 	// 		"f1": 1111,
		// 	// 		"f2": "aa",
		// 	// 		"f3": true,
		// 	// 	},
		// 	// },
		// 	"f4": map[string]any{
		// 		"f1": map[string]any{
		// 			"f1": true,
		// 		},
		// 	},
		// 	"f5": map[string]any{
		// 		"f1": map[string]any{
		// 			"f1": true,
		// 			"f2": []any{1, "", true, ""},
		// 		},
		// 	},
		// },
		// "f99": "",
	}

	type testCase struct {
		name   string
		src    map[string]interface{}
		target map[string]interface{}
	}

	testCases := []testCase{
		// {name: "same map", src: m1, target: m1},
		{name: "diff map", src: m1, target: m2},
	}

	reporter := NewTestReporter(t)

	for _, tc := range testCases {
		tc := tc
		result, err := Maps(tc.src, tc.target)
		require.NoError(t, err)

		logTitle(t, "testCase name: "+tc.name)
		reporter.GenerateReport(*result)
	}

	t.Error("force logs to show")
}

func logTitle(t *testing.T, title string) {
	t.Log("-------------------------")
	t.Logf("%v", title)
	t.Log("-------------------------")
}
