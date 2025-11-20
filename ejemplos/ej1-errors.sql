insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-01-01', 'tarjeta_credito', 'E1-BASE-UUID-0001', 'agustin.ramos@mail.com', 'anual', 30000);
select * from pago;
select * from suscripcion;

-- Debe dar error por renovación antes del período
insert into pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) values ('2024-09-01', 'tarjeta_debito', 'E1-ANTICIPADA-MAL', 'agustin.ramos@mail.com', 'anual', 30000);
select * from pago;
select * from suscripcion;
