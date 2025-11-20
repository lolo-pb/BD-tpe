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

# Fill in the data from CSV
import:
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/import.sql

# Run trigger tests
test-trigger:
	@echo ========================================================================================================================
	@echo = Tests trigger
	@echo ========================================================================================================================
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/clean.sql
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej1.sql
	@echo ========================================================================================================================
	@echo = Tests trigger errores
	@echo ========================================================================================================================
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/clean.sql
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej1-errors.sql

# Run consolidate tests
test-consolidate:
	@echo ========================================================================================================================
	@echo = Tests consolidación
	@echo ========================================================================================================================
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/clean.sql
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej1.sql -o /dev/null
	docker exec -it -u postgres pg-tpe-bd psql -f /root/ejemplos/ej2.sql

.PHONY: container setup psql test-trigger all
