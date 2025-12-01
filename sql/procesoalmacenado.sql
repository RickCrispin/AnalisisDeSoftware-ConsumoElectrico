CREATE OR REPLACE FUNCTION energy.sp_insert_reading(
  p_device_id UUID,
  p_ts TIMESTAMPTZ,
  p_power_w NUMERIC,
  p_voltage NUMERIC,
  p_current_a NUMERIC,
  p_raw JSONB
) RETURNS BIGINT
LANGUAGE plpgsql
AS $$
DECLARE
  v_reading_id BIGINT;
BEGIN
  -- Validaciones básicas
  IF p_device_id IS NULL OR p_ts IS NULL THEN
    RAISE EXCEPTION 'device_id and ts are required';
  END IF;


  INSERT INTO energy.readings(device_id, ts, power_w, voltage, current_a, raw_payload)
  VALUES (p_device_id, p_ts, p_power_w, p_voltage, p_current_a, p_raw)
  RETURNING reading_id INTO v_reading_id;


  -- Opcional: crear evento si power supera umbral (ejemplo simple)
  IF p_power_w IS NOT NULL AND p_power_w > 5000 THEN -- umbral demo en W
    INSERT INTO energy.events(home_id, device_id, event_type, severity, payload)
    VALUES (
      (SELECT home_id FROM energy.devices WHERE device_id = p_device_id),
      p_device_id,
      'high_power',
      'warning',
      jsonb_build_object('power_w', p_power_w, 'ts', p_ts)
    );
  END IF;


  RETURN v_reading_id;
END;
$$;


CREATE OR REPLACE FUNCTION energy.sp_generate_monthly_report(
  p_home_id UUID,
  p_period_start DATE,
  p_period_end DATE,
  OUT p_report_id BIGINT,
  OUT p_file_path VARCHAR
) RETURNS RECORD
LANGUAGE plpgsql
AS $$
DECLARE
  v_report_id BIGINT;
  v_path TEXT;
BEGIN
  -- Inserta metadato, la generación del archivo se delega a la app (worker) que leerá datos
  INSERT INTO energy.reports(home_id, period_start, period_end, created_at)
  VALUES (p_home_id, p_period_start, p_period_end, now())
  RETURNING report_id INTO v_report_id;


  -- Sugerir path (convención)
  v_path := format('/reports/%s/report_%s_%s.pdf', p_home_id::text, p_period_start::text, p_period_end::text);


  UPDATE energy.reports SET file_path = v_path WHERE report_id = v_report_id;


  p_report_id := v_report_id;
  p_file_path := v_path;
END;
$$;
