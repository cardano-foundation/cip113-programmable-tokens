# Cip 113 Offchain 

### How to Setup local Postgres for dev

Init local dev psql db

`createuser --superuser postgres`

`psql -U postgres`

Then create db:

```
CREATE USER cardano PASSWORD 'password';

CREATE DATABASE cip113 WITH OWNER cardano;
```

### Start with docker compose

To start the backend, db and [yaci-devkit](https://github.com/bloxbean/yaci-devkit) with docker compose, run:
```bash
./gradlew clean build -x test
docker compose up -d
```