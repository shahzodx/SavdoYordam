package domain

import "errors"

const MaxMoney int64 = 1_000_000_000_000
const MaxQuantity int64 = 1_000_000_000

// Amount is in tiyin; quantity is in thousandths. Round half up once per line.
// Decomposition avoids overflow even for the largest allowed price and quantity.
func LineTotal(price, quantity int64) (int64, error) {
	if price < 1 || price > MaxMoney || quantity < 1 || quantity > MaxQuantity {
		return 0, errors.New("invalid_amount")
	}
	whole := quantity / 1000
	if whole > MaxMoney/price {
		return 0, errors.New("amount_limit")
	}
	result := price*whole + (price*(quantity%1000)+500)/1000
	if result < 1 || result > MaxMoney {
		return 0, errors.New("amount_limit")
	}
	return result, nil
}
