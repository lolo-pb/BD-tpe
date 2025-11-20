insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-01-01', 'tarjeta_credito', 'E1-BASE-UUID-0001', 'agustin.ramos@mail.com', 'anual', 30000);

-- Debe dar error por renovación antes del período
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-09-01', 'tarjeta_debito', 'E1-ANTICIPADA-MAL', 'agustin.ramos@mail.com', 'anual', 30000);

truncate table pago;
truncate table suscripcion;

insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-01-01', 'tarjeta_credito', 'E7-FUTURO-BASE', 'nicolas.castro@mail.com', 'anual', 30000);

-- Debe dar error por solapamiento
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2023-12-20', 'efectivo', 'E7-RETRO-SUPERP', 'nicolas.castro@mail.com', 'mensual', 3000);
