package httpapi

import (
	"github.com/go-chi/chi/v5"
	"net/http"
	"time"
)

func (s *Server) report(w http.ResponseWriter, r *http.Request) error {
	tz, _ := time.LoadLocation("Asia/Tashkent")
	today := time.Now().In(tz).Format("2006-01-02")
	from, to := r.URL.Query().Get("from"), r.URL.Query().Get("to")
	if from == "" {
		from = today
	}
	if to == "" {
		to = from
	}
	start, e1 := time.ParseInLocation("2006-01-02", from, tz)
	last, e2 := time.ParseInLocation("2006-01-02", to, tz)
	if e1 != nil || e2 != nil || last.Before(start) || last.Sub(start) > 366*24*time.Hour {
		return fail(400, "invalid_period")
	}
	end := last.AddDate(0, 0, 1)
	// One SQL statement gives a single MVCC snapshot across all metrics.
	var sales, returns, received, repayments, newDebt, count, expenses, debt, low int64
	var profit *int64
	err := s.DB.QueryRow(r.Context(), `WITH sold AS (SELECT * FROM sales WHERE store_id=$1 AND created_at >= $2 AND created_at < $3),
 reversed AS (SELECT * FROM returns WHERE store_id=$1 AND created_at >= $2 AND created_at < $3),
 revenue_lines AS (SELECT i.total,round(i.cost::numeric*i.quantity/1000)::bigint AS cost_total,1 AS sign FROM sale_items i JOIN sold s ON s.id=i.sale_id
 UNION ALL SELECT i.total,i.cost_total,-1 AS sign FROM return_items i JOIN reversed r ON r.id=i.return_id)
 SELECT
 coalesce((SELECT sum(total) FROM sold),0)::bigint,
 coalesce((SELECT sum(total) FROM reversed),0)::bigint,
 coalesce((SELECT sum(amount) FROM payments WHERE store_id=$1 AND created_at >= $2 AND created_at < $3),0)::bigint,
 coalesce((SELECT sum(amount) FROM payments WHERE store_id=$1 AND kind='repayment' AND created_at >= $2 AND created_at < $3),0)::bigint,
 coalesce((SELECT sum(amount) FROM debt_entries WHERE store_id=$1 AND kind='sale' AND created_at >= $2 AND created_at < $3),0)::bigint,
 (SELECT count(*) FROM sold),
 (coalesce((SELECT sum(amount) FROM expenses WHERE store_id=$1 AND occurred_on >= $4::date AND occurred_on <= $5::date),0)-coalesce((SELECT sum(amount) FROM expense_voids WHERE store_id=$1 AND occurred_on >= $4::date AND occurred_on <= $5::date),0))::bigint,
 coalesce((SELECT sum(amount) FROM debt_entries WHERE store_id=$1),0)::bigint,
 (SELECT count(*) FROM products WHERE store_id=$1 AND NOT archived AND stock<=minimum_stock),
 CASE WHEN EXISTS(SELECT 1 FROM revenue_lines WHERE cost_total IS NULL) THEN NULL ELSE
 coalesce((SELECT sum(sign*(total-cost_total)) FROM revenue_lines),0)::bigint END`, chi.URLParam(r, "store"), start, end, from, to).Scan(&sales, &returns, &received, &repayments, &newDebt, &count, &expenses, &debt, &low, &profit)
	if err != nil {
		return err
	}
	write(w, 200, map[string]any{"from": from, "to": to, "sales": sales, "returns": returns, "net_sales": sales - returns, "received": received, "repaid_debt": repayments, "new_debt": newDebt, "sale_count": count, "expenses": expenses, "outstanding_debt": debt, "low_stock": low, "gross_profit": profit})
	return nil
}
