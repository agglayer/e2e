package engine

import (
	"os"
	"strings"
	"testing"
)

const (
	// Light is a light test
	Light = "light"
	// Heavy is a heavy test
	Heavy = "heavy"
	// Danger is a dangerous test
	Danger = "danger"
)

// ShouldRun checks if the test should run based on the tags
func ShouldRun(t *testing.T, allowedTags ...string) {
	// read tags configuration
	tagsConfiguration := os.Getenv("TAGS")

	// sanitize tags input
	tagsConfiguration = strings.TrimSpace(tagsConfiguration)
	tagsConfiguration = strings.ToLower(tagsConfiguration)

	// if no tags are set, test should run
	tags := strings.Split(tagsConfiguration, ",")
	if len(tags) == 0 || (len(tags) == 1 && len(tags[0]) == 0) {
		return
	}

	// if no allowed tags are set, test is assumed to be light
	if len(allowedTags) == 0 {
		allowedTags = append(allowedTags, Light)
	}

	// check if the test has any of the allowed tags
	tagsMap := map[string]bool{}
	for _, tag := range tags {
		tagsMap[tag] = true
	}
	for _, tag := range allowedTags {
		if tagsMap[tag] {
			return
		}
	}

	// if test allowed tags don't match with the tags configuration, skip the test
	t.Skipf("skipping test: %s", t.Name())
}
