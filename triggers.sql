-- Función que inserta evento y notificación en caso de pico
CREATE OR REPLACE FUNCTION energy.trg_after_insert_readings()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_home_id UUID;
  v_user UUID;
BEGIN
  -- Obtener home_id del device
  SELECT home_id INTO v_home_id FROM energy.devices WHERE device_id = NEW.device_id;


  -- Ejemplo de regla simple: si power_w > umbral (se puede leer de user prefs)
  IF NEW.power_w IS NOT NULL AND NEW.power_w > 5000 THEN
    INSERT INTO energy.events(home_id, device_id, event_type, severity, payload, created_at)
    VALUES (v_home_id, NEW.device_id, 'spike_power', 'high', jsonb_build_object('power_w', NEW.power_w, 'ts', NEW.ts), now());


    -- Crear notificación para todos los usuarios del hogar (simplificado)
    FOR v_user IN SELECT user_id FROM energy.user_home WHERE home_id = v_home_id
    LOOP
      INSERT INTO energy.notifications(user_id, home_id, channel, payload, status, created_at)
      VALUES (v_user, v_home_id, 'push', jsonb_build_object('title','Pico de consumo','body', format('Se detectó %s W en el dispositivo %s', NEW.power_w, NEW.device_id)), 'pending', now());
    END LOOP;
  END IF;


  RETURN NEW;
END;
$$;


-- Asociar trigger AFTER INSERT
CREATE TRIGGER trg_readings_after_insert
AFTER INSERT ON energy.readings
FOR EACH ROW
EXECUTE FUNCTION energy.trg_after_insert_readings();
