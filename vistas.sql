CREATE OR REPLACE VIEW energy.view_daily_consumption AS
SELECT
  d.home_id,
  date_trunc('day', r.ts)::date AS day,
  SUM( COALESCE(r.power_w,0) * (
      COALESCE(
        extract(epoch from lead(r.ts) OVER (PARTITION BY r.device_id ORDER BY r.ts) - r.ts),
        0
      ) / 3600.0
  )) AS total_wh
FROM energy.readings r
JOIN energy.devices d ON r.device_id = d.device_id
GROUP BY d.home_id, day
ORDER BY d.home_id, day;

CREATE OR REPLACE VIEW energy.view_top_consumers AS
SELECT
  d.device_id,
  d.home_id,
  d.model,
  SUM(COALESCE(r.power_w,0) * COALESCE(extract(epoch from lead(r.ts) OVER (PARTITION BY r.device_id ORDER BY r.ts) - r.ts),0) / 3600.0) AS total_wh
FROM energy.readings r
JOIN energy.devices d ON r.device_id = d.device_id
GROUP BY d.device_id, d.home_id, d.model
ORDER BY total_wh DESC
LIMIT 10;
