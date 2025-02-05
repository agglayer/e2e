package log

import (
	"strings"
	"testing"

	"github.com/ethereum/go-ethereum/core/types"
	ethTypes "github.com/ethereum/go-ethereum/core/types"
)

const (
	char              = "*"
	borderSize        = 3
	lineSeparatorSize = 60
)

func Tx(t *testing.T, tx *ethTypes.Transaction) {
	t.Logf("************************ TX INFO ************************")
	t.Logf("Hash: %v", tx.Hash())
	signer := types.NewEIP155Signer(tx.ChainId())
	sender, err := signer.Sender(tx)
	if err == nil {
		t.Logf("From: %v", sender)
	}
	t.Logf("Nonce: %v", tx.Nonce())
	t.Logf("ChainId: %v", tx.ChainId())
	t.Logf("To: %v", tx.To())
	t.Logf("Gas: %v", tx.Gas())
	t.Logf("GasPrice: %v", tx.GasPrice())
	t.Logf("Cost: %v", tx.Cost())

	// b, _ := tx.MarshalBinary()
	//t.Logf("RLP: ", hex.EncodeToHex(b))
	t.Logf("*********************************************************")
}

func Complements(t *testing.T, msgs ...string) {
	if len(msgs) > 0 {
		for i := 0; i < len(msgs)-1; i++ {
			t.Log(border(), "├─", msgs[i])
		}
		t.Log(border(), "└─", msgs[len(msgs)-1])
	}
}

func LineSeparator(t *testing.T) {
	t.Log(strings.Repeat(char, lineSeparatorSize))
}

func LineBreaker(t *testing.T) {
	t.Log(border())
}

func Msg(t *testing.T, args ...any) {
	t.Log(prefixArgsWithBorder(args...)...)
}

func Msgf(t *testing.T, format string, args ...any) {
	t.Logf(prefixFormatWithBorder(format), args...)
}

func Error(t *testing.T, args ...any) {
	t.Error(prefixArgsWithBorder(args...)...)
}

func Errorf(t *testing.T, format string, args ...any) {
	t.Errorf(prefixFormatWithBorder(format), args...)
}

func border() string {
	return strings.Repeat(char, borderSize)
}

func prefixArgsWithBorder(args ...any) []any {
	a := make([]any, len(args)+1)
	a[0] = border()
	if len(args) > 0 {
		copy(a[1:1+len(args)], args)
	}
	return a
}

func prefixFormatWithBorder(format string) string {
	xz := border() + " " + format
	return xz
}
