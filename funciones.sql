-- Limpieza de Triggers
-- Usamos el nombre del trigger de tu última versión: 'pago_trigger'
DROP TRIGGER IF EXISTS pago_trigger ON PAGO;

-- Limpieza de Funciones (usando las firmas correctas)
-- Tu nueva función de trigger: 'trg_nueva_suscripcion()'
DROP FUNCTION IF EXISTS trg_nueva_suscripcion() CASCADE;
-- Tu nueva función de reporte: 'consolidar_cliente(VARCHAR)'
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
CREATE OR REPLACE FUNCTION consolidar_cliente(email_cliente VARCHAR) RETURNS VOID AS $$
DECLARE
    rec RECORD;
    periodo_num INT := 0;
    periodo_inicio DATE;
    periodo_fin DATE;
    periodo_meses INT := 0;
    total_meses INT := 0;
    prev_fin DATE;
    meses_susc INT;
    siguiente_tipo VARCHAR;
    total_suscripciones INT;
    contador INT := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM suscripcion WHERE cliente_email = email_cliente) THEN
        RAISE NOTICE 'El cliente % no tiene suscripciones registradas', email_cliente;
        RETURN;
    END IF;

    SELECT COUNT(*) INTO total_suscripciones
    FROM suscripcion
    WHERE cliente_email = email_cliente;

    RAISE NOTICE '== Cliente: % ==', email_cliente;

    FOR rec IN
        SELECT s.*, p.fecha AS fecha_pago, p.medio_pago
        FROM suscripcion s
        JOIN pago p ON s.id = p.suscripcion_id
        WHERE s.cliente_email = email_cliente
        ORDER BY s.fecha_inicio
    LOOP
        contador := contador + 1;
        meses_susc := EXTRACT(YEAR FROM AGE(rec.fecha_fin, rec.fecha_inicio)) * 12 +
                      EXTRACT(MONTH FROM AGE(rec.fecha_fin, rec.fecha_inicio)) + 1;

        IF rec.tipo = 'nueva' THEN
            IF periodo_num > 0 THEN
                IF rec.fecha_inicio > prev_fin + INTERVAL '1 day' THEN
                    RAISE NOTICE '--- PERIODO DE BAJA ---';
                END IF;
            END IF;

            periodo_num := periodo_num + 1;
            periodo_inicio := rec.fecha_inicio;
            periodo_fin := rec.fecha_fin;
            periodo_meses := meses_susc;

            RAISE NOTICE 'Periodo #%', periodo_num;
        ELSE
            periodo_fin := rec.fecha_fin;
            periodo_meses := periodo_meses + meses_susc;
        END IF;

        RAISE NOTICE '  % % (% mes) | pago=% medio=% | cobertura=% a %',
            UPPER(rec.tipo), UPPER(rec.modalidad), meses_susc,
            rec.fecha_pago, rec.medio_pago, rec.fecha_inicio, rec.fecha_fin;

        total_meses := total_meses + meses_susc;
        prev_fin := rec.fecha_fin;

        -- Obtener el tipo de la siguiente suscripción
        SELECT tipo INTO siguiente_tipo
        FROM suscripcion
        WHERE cliente_email = email_cliente AND fecha_inicio > rec.fecha_inicio
        ORDER BY fecha_inicio
        LIMIT 1;

        -- Imprimir resumen si la siguiente es nueva o es la última
        IF siguiente_tipo = 'nueva' OR contador = total_suscripciones THEN
            RAISE NOTICE '  (Fin del periodo #%: % a %)  | Total periodo: % meses',
                periodo_num, periodo_inicio, periodo_fin, periodo_meses;
            RAISE NOTICE '== Total acumulado: % meses ==', total_meses;
        END IF;
    END LOOP;
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
select consolidar_cliente('valentina.sosa@mail.com');
select consolidar_cliente('julian.moreno@mail.com');
select consolidar_cliente('carla.perez21@mail.com');
// No retorna en el formato correcto



-- TODO:

- verificar ejemplos

- se tiene que llamar consolidar_cliente ( actualmente consolidar_cliente() )

- formato de retorno de consolidar
- validar respuestas bien

*/
