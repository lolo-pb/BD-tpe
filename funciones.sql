-- Limpieza de Triggers
-- Usamos el nombre del trigger de tu última versión: 'pago_trigger'
DROP TRIGGER IF EXISTS pago_trigger ON PAGO;

-- Limpieza de Funciones (usando las firmas correctas)
-- Tu nueva función de trigger: 'trg_nueva_suscripcion()'
DROP FUNCTION IF EXISTS trg_nueva_suscripcion() CASCADE; 
-- Tu nueva función de reporte: 'consolidacion(VARCHAR)'
DROP FUNCTION IF EXISTS consolidacion(VARCHAR) CASCADE;
-- Mantenemos los nombres antiguos por si acaso:
DROP FUNCTION IF EXISTS procesar_pago_suscripcion() CASCADE; 
DROP FUNCTION IF EXISTS consolidar_cliente(VARCHAR) CASCADE; 

-- Limpieza de Tablas e Índices
-- Usamos CASCADE para asegurar que las llaves foráneas y el trigger se borren
DROP TABLE IF EXISTS PAGO CASCADE; 
DROP TABLE IF EXISTS SUSCRIPCION CASCADE;
DROP INDEX IF EXISTS idx_suscripcion_cliente_email; 

-- Limpieza de Tipos
DROP TYPE IF EXISTS tipo_medio_pago CASCADE;
DROP TYPE IF EXISTS tipo_modalidad CASCADE;
DROP TYPE IF EXISTS tipo_suscripcion CASCADE;
-- TP ESPECIAL BASES DE DATOS - SQL

-- 1. TABLA PAGO
CREATE TABLE pago (
    fecha DATE NOT NULL,
    medio_pago VARCHAR(20) NOT NULL CHECK (medio_pago IN ('tarjeta_credito','tarjeta_debito','transferencia','efectivo','mercadopago')),
    id_transaccion VARCHAR(100) PRIMARY KEY,
    cliente_email VARCHAR(255) NOT NULL,
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual','anual')),
    monto NUMERIC(12,2) CHECK (monto > 0),
    suscripcion_id INT
);

-- 2. TABLA SUSCRIPCION
CREATE TABLE suscripcion (
    id SERIAL PRIMARY KEY,
    cliente_email VARCHAR(255) NOT NULL,
    tipo VARCHAR(20) NOT NULL CHECK (tipo IN ('nueva','renovacion')),
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual','anual')),
    fecha_inicio DATE NOT NULL,
    fecha_fin DATE NOT NULL
);

-- 3. TRIGGER PARA CARGAR SUSCRIPCION
CREATE OR REPLACE FUNCTION trg_nueva_suscripcion() RETURNS TRIGGER AS $$
DECLARE
    ult_id INT;
    ult_fin DATE;
BEGIN
    SELECT id, fecha_fin
    INTO ult_id, ult_fin
    FROM suscripcion
    WHERE cliente_email = NEW.cliente_email
    ORDER BY fecha_fin DESC
    LIMIT 1;

    IF ult_id IS NULL THEN
        INSERT INTO suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
        VALUES (
            NEW.cliente_email,
            'nueva',
            NEW.modalidad,
            NEW.fecha,
            CASE WHEN NEW.modalidad = 'mensual' THEN NEW.fecha + INTERVAL '1 month' - INTERVAL '1 day'
                 ELSE NEW.fecha + INTERVAL '1 year' - INTERVAL '1 day' END
        ) RETURNING id INTO NEW.suscripcion_id;
        RETURN NEW;
    END IF;

    IF NEW.fecha <= ult_fin AND NEW.fecha >= ult_fin - INTERVAL '30 days' THEN
        INSERT INTO suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
        VALUES (
            NEW.cliente_email,
            'renovacion',
            NEW.modalidad,
            ult_fin + INTERVAL '1 day',
            CASE WHEN NEW.modalidad = 'mensual' THEN (ult_fin + INTERVAL '1 day') + INTERVAL '1 month' - INTERVAL '1 day'
                 ELSE (ult_fin + INTERVAL '1 day') + INTERVAL '1 year' - INTERVAL '1 day' END
        ) RETURNING id INTO NEW.suscripcion_id;
        RETURN NEW;
    END IF;

    INSERT INTO suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
    VALUES (
        NEW.cliente_email,
        'nueva',
        NEW.modalidad,
        NEW.fecha,
        CASE WHEN NEW.modalidad = 'mensual' THEN NEW.fecha + INTERVAL '1 month' - INTERVAL '1 day'
             ELSE NEW.fecha + INTERVAL '1 year' - INTERVAL '1 day' END
    ) RETURNING id INTO NEW.suscripcion_id;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pago_trigger
BEFORE INSERT ON pago
FOR EACH ROW
EXECUTE FUNCTION trg_nueva_suscripcion();

-- 4. FUNCIÓN DE CONSOLIDACIÓN
CREATE OR REPLACE FUNCTION consolidacion(email_busqueda VARCHAR)
RETURNS TABLE(
    cliente VARCHAR,
    id_suscripcion INT,
    tipo VARCHAR,
    modalidad VARCHAR,
    inicio DATE,
    fin DATE,
    meses INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        s.cliente_email,
        s.id,
        s.tipo,
        s.modalidad,
        s.fecha_inicio,
        s.fecha_fin,
        EXTRACT(MONTH FROM AGE(s.fecha_fin, s.fecha_inicio))::INT AS meses
    FROM suscripcion s
    WHERE s.cliente_email = email_busqueda
    ORDER BY fecha_inicio;
END;
$$ LANGUAGE plpgsql;