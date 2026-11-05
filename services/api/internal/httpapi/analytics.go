package httpapi

import (
	"encoding/json"
	"github.com/go-chi/chi/v5"
	"net/http"
	"time"
)

func (s *Server) analytics(w http.ResponseWriter, r *http.Request) error {
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
	previous := start.Add(-end.Sub(start))
	var raw []byte
	err := s.DB.QueryRow(r.Context(), `WITH days AS (SELECT generate_series($4::date,$5::date,'1 day'::interval)::date AS day),
 sold AS (SELECT * FROM sales WHERE store_id=$1 AND created_at >= $2 AND created_at < $3),
 reversed AS (SELECT * FROM returns WHERE store_id=$1 AND created_at >= $2 AND created_at < $3),
 product_lines AS (
 SELECT i.product_id,i.name,i.quantity,i.total FROM sale_items i JOIN sold s ON s.id=i.sale_id
 UNION ALL SELECT ri.product_id,p.name,-ri.quantity,-ri.total FROM return_items ri JOIN reversed r ON r.id=ri.return_id JOIN products p ON p.store_id=ri.store_id AND p.id=ri.product_id),
 top_products AS (SELECT l.product_id,min(l.name) AS name,p.unit,sum(l.quantity)::bigint AS quantity,sum(l.total)::bigint AS total FROM product_lines l JOIN products p ON p.id=l.product_id AND p.store_id=$1 GROUP BY l.product_id,p.unit ORDER BY sum(l.total) DESC,l.product_id LIMIT 10)
 SELECT jsonb_build_object('daily',(SELECT coalesce(jsonb_agg(jsonb_build_object('date',day,'net_sales',
 coalesce((SELECT sum(total) FROM sold WHERE (created_at AT TIME ZONE 'Asia/Tashkent')::date=day),0)-coalesce((SELECT sum(total) FROM reversed WHERE (created_at AT TIME ZONE 'Asia/Tashkent')::date=day),0),
 'received',coalesce((SELECT sum(amount) FROM payments WHERE store_id=$1 AND (created_at AT TIME ZONE 'Asia/Tashkent')::date=day),0)) ORDER BY day),'[]'::jsonb) FROM days),
 'products',(SELECT coalesce(jsonb_agg(to_jsonb(t)),'[]'::jsonb) FROM top_products t),
 'previous_net_sales',coalesce((SELECT sum(total) FROM sales WHERE store_id=$1 AND created_at >= $6 AND created_at < $2),0)-coalesce((SELECT sum(total) FROM returns WHERE store_id=$1 AND created_at >= $6 AND created_at < $2),0))`, chi.URLParam(r, "store"), start, end, from, to, previous).Scan(&raw)
	if err != nil {
		return err
	}
	write(w, 200, json.RawMessage(raw))
	return nil
}
