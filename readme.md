# PostgreSQL with pgBackRest Docker Image
Docker image: `yourusername/postgres-pgbackrest`
This image extends the official PostgreSQL image with integrated pgBackRest for automated backups and WAL archiving.
## Quick Start
### Basic Usage

```bash
docker run -d \
  --name postgres-pgbackrest \
  -e POSTGRES_PASSWORD=yourpassword \
  -e ENV_PGBACKREST_STANZA=mydb \
  yourusername/postgres-pgbackrest:latest
```

&nbsp;
### docker-compose.yml Example

```yaml
services:
  postgres:
    image: yourusername/postgres-pgbackrest:latest
    environment:
      POSTGRES_PASSWORD: securepassword123
      POSTGRES_DB: myappdb
      ENV_PGBACKREST_STANZA: production
      ENV_PGBACKREST_CRON_SCHEDULE: "0 2 * * *"
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - pgbackrest_repo:/var/lib/pgbackrest
    ports:
      - "5432:5432"

volumes:
  postgres_data:
  pgbackrest_repo:
```

&nbsp;
## Environment Variables
### PostgreSQL Environment Variables
- `POSTGRES_PASSWORD` - **Required** - Superuser password
- `POSTGRES_USER` - (default: `postgres`) - PostgreSQL username
- `POSTGRES_DB` - (default: same as `POSTGRES_USER`) - Database name to create
- `PGDATA` - (default: `/var/lib/postgresql/data`) - Data directory path
### pgBackRest Environment Variables
- `ENV_PGBACKREST_STANZA` - (default: `${POSTGRES_DB:-postgres}`) - pgBackRest stanza name (logical backup group)
- `ENV_PGBACKREST_CRON_SCHEDULE` - (default: `"0 0 * * *"`) - Backup schedule in cron format (supercronic)
- `ENV_PGBACKREST_CONFIG_FILE_PATH` - (default: `/etc/pgbackrest/conf/pgbackrest.conf`) - pgBackRest config file path
- `ENV_FULL_BACKUP_INTERVAL_DAYS` - (default: 7) - Interval (days) to force full backup instead of incremental
- `ENV_PGBACKREST_FULLBACKUP_ON_STARTUP` - (default: true) - Whether to perform a full backup on container startup

&nbsp;
## Backup Schedule Examples
```bash
# Daily at 2:00 AM
ENV_PGBACKREST_CRON_SCHEDULE="0 2 * * *"

# Every 6 hours
ENV_PGBACKREST_CRON_SCHEDULE="0 */6 * * *"

# Every 30 minutes (development/testing)
ENV_PGBACKREST_CRON_SCHEDULE="*/30 * * * *"

# Every Sunday at 3:00 AM
ENV_PGBACKREST_CRON_SCHEDULE="0 3 * * 0"
```

&nbsp;
## Custom Configuration Files
### PostgreSQL Custom Config Example
```yaml
volumes:
  - ./postgres_custom.conf:/etc/postgresql/postgresql.conf:ro
command: postgres -c config_file=/etc/postgresql/postgresql.conf
```
PostgreSQL reads `/etc/postgresql/postgresql.conf` if it exists. The image automatically includes pgBackRest required settings (archive_mode=on, etc.) via overrides.

### pgBackRest Custom Config Example
```yaml
environment:
  ENV_PGBACKREST_STANZA: mystanza
volumes:
  - ./pgbackrest_custom.conf:/etc/pgbackrest/conf/pgbackrest.conf
```

&nbsp;
## Backup Management
### Manual Backup
```bash
docker exec <container> pgbackrest --stanza=<stanza-name> backup
```
### Check Backup Info
```bash
docker exec <container> pgbackrest info
```
### Restore
```bash
# Restore from latest backup
docker exec <container> pgbackrest --stanza=<stanza> restore

# Restore to specific point in time
docker exec <container> pgbackrest --stanza=<stanza> \
  --type=time --target="2026-01-19 12:00:00" restore
```