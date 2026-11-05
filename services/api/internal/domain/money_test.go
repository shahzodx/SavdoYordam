package domain

import "testing"

func TestLineTotal(t *testing.T) {
	for _, tc := range []struct {
		price, qty, want int64
		bad              bool
	}{
		{1250000, 1500, 1875000, false}, {101, 500, 51, false}, {1, 1, 0, true},
		{MaxMoney, 1000, MaxMoney, false}, {MaxMoney, MaxQuantity, 0, true}, {-1, 1000, 0, true},
	} {
		got, err := LineTotal(tc.price, tc.qty)
		if (err != nil) != tc.bad || got != tc.want {
			t.Fatalf("%+v: %d %v", tc, got, err)
		}
	}
}
