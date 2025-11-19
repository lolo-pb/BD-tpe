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

CREATE OR REPLACE FUNCTION trg_nueva_suscripcion() RETURNS TRIGGER AS $$
DECLARE
    ult_id INT;
    ult_inicio DATE;
    ult_fin DATE;
    v_posible_fin DATE; -- Variable para calcular la fecha fin teórica
BEGIN
    SELECT id, fecha_inicio, fecha_fin
    INTO ult_id, ult_inicio, ult_fin
    FROM suscripcion
    WHERE cliente_email = NEW.cliente_email
    ORDER BY fecha_fin DESC
    LIMIT 1;

    -- Si no existe suscripción previa, es una nueva suscripción
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

    -- 1. Calcular cuándo terminaría esta nueva suscripción si la aceptamos tal cual
    v_posible_fin := CASE WHEN NEW.modalidad = 'mensual' THEN NEW.fecha + INTERVAL '1 month' - INTERVAL '1 day'
                          ELSE NEW.fecha + INTERVAL '1 year' - INTERVAL '1 day' END;

    -- 2. Lógica de Renovación
    IF NEW.fecha <= ult_fin AND NEW.fecha >= (ult_fin - INTERVAL '30 days') THEN
        
        INSERT INTO suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
        VALUES (
            NEW.cliente_email,
            'renovacion',
            NEW.modalidad,
            ult_fin + INTERVAL '1 day',
            CASE WHEN NEW.modalidad = 'mensual' THEN (ult_fin + INTERVAL '1 day') + INTERVAL '1 month' - INTERVAL '1 day'
                 ELSE (ult_fin + INTERVAL '1 day') + INTERVAL '1 year' - INTERVAL '1 day' END
                 -- Esto se suma y resta para que queden bien las fechas: 
                 -- termina el 31 dic => hace 1 ene -> 1->fev -> 31 v 29 de enero segun corresponda
        ) RETURNING id INTO NEW.suscripcion_id;
        RETURN NEW;
    END IF;

    -- 3. Chequeo de Solapamiento
    -- La suscripción es válida SOLO SI:
    -- (Termina antes de que empiece la vieja) O (Empieza después de que termine la vieja)
    -- Por el contrario, FALLA si: (Empieza antes del fin viejo) Y (Termina después del inicio viejo)
    IF (NEW.fecha <= ult_fin) AND (v_posible_fin >= ult_inicio) THEN
        RAISE EXCEPTION 'Solapamiento: La suscripción antigua inicia el %, y tu nueva suscripción terminaría el %. Se superponen.', ult_inicio, v_posible_fin;
    END IF;

    -- VALIDACIÓN: Bloqueo de renovación prematura
    -- Si la fecha del pago es ANTERIOR a la ventana permitida (30 días antes del fin)
    IF NEW.fecha < (ult_fin - INTERVAL '30 days') THEN
        RAISE EXCEPTION 'Renovación anticipada: Faltan más de 30 días para el vencimiento (Vence: %). Intente nuevamente más cerca de la fecha.', ult_fin;
    END IF;

    -- 4. Insert
    INSERT INTO suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
    VALUES (
        NEW.cliente_email,
        'nueva',
        NEW.modalidad,
        NEW.fecha,
        v_posible_fin
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

/*
 -- EJEMPLOS -- 
Nota: Ojo que  el copy del pdf aveces pone el "'" mal y no corre 

-- Ej(1)  funciona
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-01-01','tarjeta_credito', 'UUID-001', 'valentina.sosa@mail.com','mensual',3000);
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-01-28','tarjeta_debito', 'UUID-002', 'valentina.sosa@mail.com','mensual',3000);
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2023-03-10', 'mercadopago', 'UUID-003', 'julian.moreno@mail.com', 'anual', 30000);
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-03-01', 'tarjeta_credito', 'UUID-004', 'julian.moreno@mail.com', 'anual', 30000);
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2022-08-01', 'efectivo', 'UUID-005', 'carla.perez21@mail.com', 'mensual', 3000);
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2022-10-10', 'transferencia', 'UUID-006', 'carla.perez21@mail.com', 'mensual', 3000);


-- Ej(2)

-- Ej(2) ejemplos y notas
-- Esta inserción base debe crear la suscripción inicial:
INSERT INTO pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto)
    VALUES ('2024-01-01', 'tarjeta_credito', 'E1-BASE-UUID-0001', 'agustin.ramos@mail.com', 'anual', 30000);
-- Esta inserción representa una renovación anticipada (>30 días antes del fin) y debe ser RECHAZADA por el trigger:
INSERT INTO pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto)
    VALUES ('2024-09-01', 'tarjeta_debito', 'E1-ANTICIPADA-MAL', 'agustin.ramos@mail.com', 'anual', 30000);

-- Caso solapamiento/retroactivo:
-- Si se inserta una primera suscripción con fecha '2024-01-01' para 'nicolas.castro@mail.com',
-- un pago con fecha anterior al inicio de esa suscripción (por ejemplo '2023-12-20') debe ser RECHAZADO.
INSERT INTO pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto)
    VALUES ('2024-01-01', 'tarjeta_credito', 'E7-FUTURO-BASE', 'nicolas.castro@mail.com', 'anual', 30000);
-- Este siguiente insert debe ser rechazado por solapamiento (fecha anterior al inicio):
INSERT INTO pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto)
    VALUES ('2023-12-20', 'efectivo', 'E7-RETRO-SUPERP', 'nicolas.castro@mail.com', 'mensual', 3000);

-- Ej(3)
// Inserts del Ej 1
select consolidacion('valentina.sosa@mail.com');
select consolidacion('julian.moreno@mail.com');
select consolidacion('carla.perez21@mail.com');
// No retorna en el formato correcto



-- TODO:

- verificar ejemplos 

- se tiene que llamar consolidar_cliente ( actualmente consolidacion() )

- formato de retorno de consolidar
- validar respuestas bien

*/