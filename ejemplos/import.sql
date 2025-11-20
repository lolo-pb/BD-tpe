\copy pago (fecha, medio_pago, id_transaccion, cliente_email, modalidad, monto) from '/root/pagos.csv' with (format csv, header);
