DB_NAME=bench
DB_USER=test
DB_PORT=5432
DB_PASSWORD=test

.PHONY: postgres
postgres:
	docker run \
		-p $(DB_PORT)\:5432 \
		-e POSTGRES_USER=$(DB_USER) \
		-e POSTGRES_DB=$(DB_NAME) \
		-e POSTGRES_PASSWORD=$(DB_PASSWORD) \
		postgres:12.4-alpine

.PHONY: sql-repl
sql-repl:
	PGPASSWORD=$(DB_PASSWORD) psql -h localhost -p $(DB_PORT) -d $(DB_NAME) -U $(DB_USER)

.PHONY: stats
stats: main
	PGPASSWORD=$(DB_PASSWORD) psql -h localhost -p $(DB_PORT) -d $(DB_NAME) -U $(DB_USER) -f stats.sql

.PHONY: main
main:
	stack runghc \
		--package postgresql-simple \
		--package relude \
		--package uuid-types \
		--package bytestring \
		--package random \
		--package async \
		--package amazonka-core \
		--package amazonka \
		--package amazonka-s3 \
		--package amazonka-sqs \
		--package aeson \
		--package lens \
		--package lens-aeson \
		Main.hs