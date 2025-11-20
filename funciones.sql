-- Limpieza de Triggers
-- Usamos el nombre del trigger de tu última versión: 'pago_trigger'
DROP TRIGGER IF EXISTS pago_trigger ON PAGO;

-- Limpieza de Funciones (usando las firmas correctas)
-- Tu nueva función de trigger: 'trg_nueva_suscripcion()'
DROP FUNCTION IF EXISTS trg_nueva_suscripcion() CASCADE;
-- Tu nueva función de reporte: 'consolidacion(VARCHAR)'
DROP FUNCTION IF EXISTS consolidar_cliente(VARCHAR) CASCADE;

-- Limpieza de Tablas e Índices
-- Usamos CASCADE para asegurar que las llaves foráneas y el trigger se borren
DROP TABLE IF EXISTS PAGO CASCADE;
DROP TABLE IF EXISTS SUSCRIPCION CASCADE;

-- 1. TABLA PAGO
CREATE TABLE pago (
    fecha DATE NOT NULL,
    medio_pago VARCHAR(20) NOT NULL CHECK (medio_pago IN ('tarjeta_credito','tarjeta_debito','transferencia','efectivo','mercadopago')),
    id_transaccion VARCHAR(100) PRIMARY KEY,
    cliente_email VARCHAR(255) NOT NULL,
    modalidad VARCHAR(10) NOT NULL CHECK (modalidad IN ('mensual','anual')),
    monto NUMERIC(12,2) CHECK (monto > 0) NOT NULL,
    suscripcion_id INT NOT NULL
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
    sol_id INT;
    sol_inicio DATE;
    sol_fin DATE;
    v_posible_fin DATE; -- Variable para calcular la fecha fin teórica
begin
    -- Calcular cuándo terminaría esta nueva suscripción si la aceptamos tal cual
    v_posible_fin := case when new.modalidad = 'mensual' then new.fecha + interval '1 month' - interval '1 day'
                            else new.fecha + interval '1 year' - interval '1 day' end;

    -- 1. Lógica de Renovación
    -- Si el pago está dentro de los últimos 30 días de la última suscripción es una renovación
    -- Si conicide con el período de suscripción pero es previo a los últimos 30 días es error por renovación anticipada
    select id, fecha_inicio, fecha_fin
    into ult_id, ult_inicio, ult_fin
    from suscripcion
    where cliente_email = new.cliente_email
    order by fecha_fin desc
    limit 1;
    if new.fecha <= ult_fin and new.fecha >= (ult_fin - interval '30 days') then
        insert into suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
        values (
            new.cliente_email,
            'renovacion',
            new.modalidad,
            ult_fin + interval '1 day',
            case when new.modalidad = 'mensual' then (ult_fin + interval '1 day') + interval '1 month' - interval '1 day'
                 else (ult_fin + interval '1 day') + interval '1 year' - interval '1 day' end
                 -- Esto se suma y resta para que queden bien las fechas:
                 -- termina el 31 dic => hace 1 ene -> 1->fev -> 31 v 29 de enero segun corresponda
        ) returning id into new.suscripcion_id;
        return new;
    elsif new.fecha >= ult_inicio and new.fecha < (ult_fin - interval '30 days') then
        raise exception 'Renovación anticipada: Faltan más de 30 días para el vencimiento (Vence: %). Intente nuevamente más cerca de la fecha.', ult_fin;
    end if;

    -- 2. Chequeo de Solapamiento
    select id, fecha_inicio, fecha_fin
    into sol_id, sol_inicio, sol_fin
    from suscripcion
    where cliente_email = new.cliente_email
        and v_posible_fin >= fecha_inicio
        and fecha_fin >= new.fecha
    limit 1;
    if sol_id is not null then
        raise exception 'Solapamiento: Intervalo antiguo [% a %], nueva suscripción [% a %].', sol_inicio, sol_fin, NEW.fecha, v_posible_fin;
    end if;

    -- 3. En el caso que no es renovación y no hay solapamiento, se inserta como nueva
    insert into suscripcion(cliente_email, tipo, modalidad, fecha_inicio, fecha_fin)
    values (
        new.cliente_email,
        'nueva',
        new.modalidad,
        new.fecha,
        v_posible_fin
    ) returning id into new.suscripcion_id;
    return new;
end;
$$ LANGUAGE plpgsql;

CREATE TRIGGER pago_trigger
BEFORE INSERT ON pago
FOR EACH ROW
EXECUTE FUNCTION trg_nueva_suscripcion();

-- 4. FUNCIÓN DE CONSOLIDACIÓN
CREATE OR REPLACE FUNCTION consolidar_cliente(email_busqueda VARCHAR)
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
