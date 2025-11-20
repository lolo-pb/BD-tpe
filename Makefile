# Run the SQL script to set up tables and db trigger
setup: container
	sleep 5 # Wait for the container to start up, otherwise psql fails
	docker exec -it -u postgres pg-tpe-bd psql -f /root/funciones.sql

# Pull and create the container
container:
	docker pull postgres:17.7-trixie
	-docker stop pg-tpe-bd
	-docker rm pg-tpe-bd
	docker run -v $(PWD):/root --name pg-tpe-bd -td -e POSTGRES_PASSWORD=postgres postgres:17.7-trixie

# Start an interactive psql shell
psql:
	docker exec -it -u postgres pg-tpe-bd psql

# Run examples
examples:
	@echo ========================================================================================================================
	@echo = Ejemplo 1
	@echo ========================================================================================================================
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/clean.sql
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej1.sql
	@echo ========================================================================================================================
	@echo = Ejemplo 1 errores
	@echo ========================================================================================================================
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/clean.sql
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej1-errors.sql

.PHONY: container setup psql examples all
