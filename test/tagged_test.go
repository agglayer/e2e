package test

import (
	"testing"

	"github.com/agglayer/e2e/test/tools/engine"
	"github.com/stretchr/testify/assert"
)

func TestUnchecked(t *testing.T) {
	assert.True(t, true)
}

func TestUntagged(t *testing.T) {
	assert.True(t, true)
}

func TestLight(t *testing.T) {
	engine.ShouldRun(t, engine.Light)
	assert.True(t, true)
}

func TestHeavy(t *testing.T) {
	engine.ShouldRun(t, engine.Heavy)
	assert.True(t, true)
}

func TestDanger(t *testing.T) {
	engine.ShouldRun(t, engine.Danger)
	assert.True(t, true)
}

func TestLightAndDanger(t *testing.T) {
	engine.ShouldRun(t, engine.Light, engine.Danger)
	assert.True(t, true)
}

func TestHeavyAndDanger(t *testing.T) {
	engine.ShouldRun(t, engine.Heavy, engine.Danger)
	assert.True(t, true)
}
