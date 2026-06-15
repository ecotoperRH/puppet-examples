---
source-path: modules/profile_app_stack
---

# Migration Plan: profile_app_stack

**TLDR**: This module manages a Python web application stack with PostgreSQL database integration, systemd service management, and monitoring. It handles the complete lifecycle from Python environment setup to application deployment, database configuration, service management, and monitoring integration.

## Service Type and Instances

**Service Type**: Web Application

**Configured Instances**:
- **myapp-api**: Python web application
  - Location/Path: /opt/myapp-api
  - Port/Socket: 8000
  - Key Config: Gunicorn with uvicorn workers, PostgreSQL database backend

## File Structure

```
modules/profile_app_stack/data/common.yaml
modules/profile_app_stack/data/environment/production.yaml
modules/profile_app_stack/data/environment/staging.yaml
modules/profile_app_stack/manifests/app.pp
modules/profile_app_stack/manifests/database.pp
modules/profile_app_stack/manifests/init.pp
modules/profile_app_stack/manifests/monitoring.pp
modules/profile_app_stack/manifests/python.pp
modules/profile_app_stack/manifests/service.pp
modules/profile_app_stack/templates/app.env.erb
modules/profile_app_stack/templates/app.service.epp
modules/profile_app_stack/templates/logrotate.conf.erb
```

## Module Explanation

The module performs operations in this order:

1. **profile_app_stack** (`manifests/init.pp`):
   - Sets class parameters from Hiera: app_name=myapp-api, app_repo=https://github.com/example-org/myapp-api.git, app_revision=main (overridden in environments), app_port=8000, app_dir=/opt/myapp-api, app_user=myapp, app_group=myapp, db_host=localhost (overridden in environments), db_port=5432, db_name=myapp_db, db_user=myapp_app, db_password=(encrypted), worker_count=2 (overridden in environments), worker_class=uvicorn.workers.UvicornWorker, max_requests=1000 (overridden in environments), graceful_timeout=30, log_dir=/var/log/myapp-api, log_level=info (overridden in environments), secret_key=(encrypted)
   - Contains profile_app_stack::python class
   - Contains profile_app_stack::database class
   - Contains profile_app_stack::app class
   - Contains profile_app_stack::service class
   - Contains profile_app_stack::monitoring class
   - Sets ordering: python -> database -> app ~> service -> monitoring (app changes notify service restart)
   - Resources: None (orchestration only)

2. **profile_app_stack::python** (`manifests/python.pp`):
   - Sets variables from Hiera: python_version=python3, pip_packages=['uvicorn', 'gunicorn', 'psycopg2-binary']
   - Installs packages: python3, python3-pip, python3-venv, python3-dev, git, build-essential
   - Creates app group: myapp (system=true)
   - Creates app user: myapp (gid=myapp, home=/opt/myapp-api, shell=/bin/bash, system=true)
   - Creates log directory: /var/log/myapp-api (owner=myapp, group=myapp, mode=0755)
   - Deploys logrotate configuration:
     - Template: logrotate.conf.erb → /etc/logrotate.d/myapp-api (owner=root, group=root, mode=0644)
     - Sets: log_dir=/var/log/myapp-api, log_rotate_count=7, log_max_size=100M, app_name=myapp-api
   - Resources: package (6), group (1), user (1), file (2)

3. **profile_app_stack::database** (`manifests/database.pp`):
   - Conditional: If db_host is 'localhost' (true in staging, false in production):
     - Installs packages: postgresql, postgresql-contrib, libpq-dev
     - Manages service: postgresql (ensure=running, enable=true)
     - Creates database user via exec: create_db_user (creates myapp_app user with password)
     - Creates database via exec: create_database (creates myapp_db owned by myapp_app)
     - Grants privileges via exec: grant_db_privileges (grants ALL to myapp_app on myapp_db)
   - Installs package: cron
   - Deploys backup script: /usr/local/bin/db-backup.sh (owner=root, group=myapp, mode=0750)
   - Creates cron job: database_backup (runs at 2:30 AM daily)
   - Resources: package (4), service (1), exec (3), file (1), cron (1)

4. **profile_app_stack::app** (`manifests/app.pp`):
   - Clones application repository:
     - Source: https://github.com/example-org/myapp-api.git
     - Destination: /opt/myapp-api
     - Revision: main (staging) or v2.4.1 (production)
     - Owner: myapp, Group: myapp
   - Creates Python virtual environment: /opt/myapp-api/venv
   - Installs Python requirements from requirements.txt
   - Installs additional pip packages:
     - uvicorn
     - gunicorn
     - psycopg2-binary
   - Deploys environment file:
     - Template: app.env.erb → /opt/myapp-api/.env (owner=myapp, group=myapp, mode=0600)
     - Sets: DATABASE_URL, APP_NAME=myapp-api, APP_PORT=8000, SECRET_KEY, LOG_LEVEL, LOG_DIR, WORKERS, DEBUG, ALLOWED_HOSTS, CORS_ORIGINS
   - Deploys health check script: /usr/local/bin/app-healthcheck.sh (owner=root, group=root, mode=0755)
   - Runs database migrations if alembic is initialized (refreshonly, triggered by repository updates)
   - Resources: vcsrepo (1), exec (3+3 for pip packages), file (2)
   - **notifies**: Changes to app files ~> service[myapp-api]

5. **profile_app_stack::service** (`manifests/service.pp`):
   - Deploys systemd unit file:
     - Template: app.service.epp → /etc/systemd/system/myapp-api.service (owner=root, group=root, mode=0644)
     - Sets: app_name=myapp-api, app_dir=/opt/myapp-api, app_user=myapp, app_group=myapp, app_port=8000, worker_count=2 (staging) or 8 (production), worker_class=uvicorn.workers.UvicornWorker, max_requests=100 (staging) or 5000 (production), graceful_timeout=30, log_dir=/var/log/myapp-api, log_level=debug (staging) or warning (production)
   - Runs systemd daemon-reload via exec (refreshonly)
   - Manages service: myapp-api (ensure=running, enable=true)
   - Resources: file (1), exec (1), service (1)
   - **notifies**: file[/etc/systemd/system/myapp-api.service] ~> exec[app_stack_systemd_daemon_reload]
   - **subscribes**: service[myapp-api] subscribes to file[/opt/myapp-api/.env]

6. **profile_app_stack::monitoring** (`manifests/monitoring.pp`):
   - Defines virtual resources (not realized by default):
     - @package: prometheus-node-exporter
     - @service: prometheus-node-exporter
     - @package: prometheus-pushgateway
     - @cron: push_app_metrics (runs every 5 minutes)
   - Conditional: If environment is 'production':
     - Realizes package: prometheus-node-exporter
     - Realizes service: prometheus-node-exporter
     - Realizes package: prometheus-pushgateway
     - Realizes cron: push_app_metrics
   - Creates cron job: app_health_check (runs every 2 minutes)
   - Resources: cron (1), virtual resources (4)

## Variables

**Variable Flow Summary**: 21 variables across 3 Hiera levels (common, environment/production, environment/staging)

### Variable Definitions

**common.yaml (defaults)** → Migration note: Base defaults for all nodes
- `profile_app_stack::app_name`: `myapp-api` (type: string)
- `profile_app_stack::app_repo`: `https://github.com/example-org/myapp-api.git` (type: string)
- `profile_app_stack::app_revision`: `main` (type: string)
- `profile_app_stack::app_port`: `8000` (type: integer)
- `profile_app_stack::app_dir`: `/opt/myapp-api` (type: string)
- `profile_app_stack::app_user`: `myapp` (type: string)
- `profile_app_stack::app_group`: `myapp` (type: string)
- `profile_app_stack::python_version`: `python3` (type: string)
- `profile_app_stack::pip_packages`: (type: array)
  ```yaml
  - uvicorn
  - gunicorn
  - psycopg2-binary
  ```
- `profile_app_stack::db_host`: `localhost` (type: string)
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::db_name`: `myapp_db` (type: string)
- `profile_app_stack::db_user`: `myapp_app` (type: string)
- `profile_app_stack::db_password`: `ENC[PKCS7,MIIBygYJKoZIhvcNAQcDoIIBuzCCAbcCAQAxggEhMIIBHQIBADAFMAACAQEwDQYJKoZIhvcNAQEBBQAEggEAdbPassword]` (type: string, encrypted)
- `profile_app_stack::worker_count`: `2` (type: integer)
- `profile_app_stack::worker_class`: `uvicorn.workers.UvicornWorker` (type: string)
- `profile_app_stack::max_requests`: `1000` (type: integer)
- `profile_app_stack::graceful_timeout`: `30` (type: integer)
- `profile_app_stack::log_dir`: `/var/log/myapp-api` (type: string)
- `profile_app_stack::log_level`: `info` (type: string)
- `profile_app_stack::log_max_size`: `100M` (type: string)
- `profile_app_stack::log_rotate_count`: `7` (type: integer)

**environment/production.yaml (environment overrides)** → Migration note: Production-specific variables
- `profile_app_stack::app_revision`: `v2.4.1` (type: string)
- `profile_app_stack::worker_count`: `8` (type: integer)
- `profile_app_stack::max_requests`: `5000` (type: integer)
- `profile_app_stack::log_level`: `warning` (type: string)
- `profile_app_stack::db_host`: `db-primary.prod.internal` (type: string)
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::secret_key`: `ENC[PKCS7,MIIBygYJKoZIhvcNAQcDoIIBuzCCAbcCAQAxggEhMIIBHQIBADAFMAACAQEwDQYJKoZIhvcNAQEBBQAEggEAProdSecret]` (type: string, encrypted)

**environment/staging.yaml (environment overrides)** → Migration note: Staging-specific variables
- `profile_app_stack::app_revision`: `main` (type: string)
- `profile_app_stack::worker_count`: `1` (type: integer)
- `profile_app_stack::max_requests`: `100` (type: integer)
- `profile_app_stack::log_level`: `debug` (type: string)
- `profile_app_stack::db_host`: `localhost` (type: string)
- `profile_app_stack::secret_key`: `staging-not-secret-at-all` (type: string)

### Variable Migration Summary

- **Common defaults**: 21 variables from common.yaml (base configuration for all nodes)
- **Environment-specific variables**: 6 variables that vary by deployment environment (production, staging)
- **Encrypted variables**: 2 variables that are encrypted (eyaml) and need secure storage (db_password, secret_key)

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **profile_app_stack::app_revision**: defined at common, environment/production, environment/staging, merge strategy: first
- **profile_app_stack::worker_count**: defined at common, environment/production, environment/staging, merge strategy: first
- **profile_app_stack::max_requests**: defined at common, environment/production, environment/staging, merge strategy: first
- **profile_app_stack::log_level**: defined at common, environment/production, environment/staging, merge strategy: first
- **profile_app_stack::db_host**: defined at common, environment/production, environment/staging, merge strategy: first
- **profile_app_stack::secret_key**: defined at environment/production, environment/staging, merge strategy: first

### Merge Strategy Notes

- All variables use `first` merge strategy - first value found wins, no merging

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (forge, version: 9.7.0)
- puppetlabs-concat (forge, version: 9.0.2)
- puppetlabs-firewall (forge, version: 8.1.3)
- puppetlabs-vcsrepo (forge, version: 6.1.0)
- puppet-redis (forge, version: 11.0.0)
- puppetlabs-apt (forge, version: 9.4.0)

**System package dependencies**:
- python3, python3-pip, python3-venv, python3-dev
- git, build-essential
- postgresql, postgresql-contrib, libpq-dev (when db_host is localhost)
- cron
- prometheus-node-exporter, prometheus-pushgateway (in production)

**Service dependencies**:
- postgresql (when db_host is localhost)
- prometheus-node-exporter (in production)

## Puppet Facts Used

- `$facts['environment']` - Current environment (production, staging)
- `$facts['kernel']` - Kernel type (Linux, Windows, etc.)

## Template Conversion Notes

### app.env.erb
- **Variables used**: db_url, app_name, app_port, secret_key, log_level, log_dir, worker_count, facts['environment']
- **Conditional rendering**: Uses if/else block to set different values for production vs. non-production environments
- **Complex expressions**: None

### app.service.epp
- **Variables used**: app_name, app_dir, app_user, app_group, app_port, worker_count, worker_class, max_requests, graceful_timeout, log_dir, log_level
- **Complex expressions**: Calculates TimeoutStopSec as graceful_timeout + 5
- **Conditional rendering**: None

### logrotate.conf.erb
- **Variables used**: log_dir, log_rotate_count, log_max_size, app_name
- **Complex expressions**: None
- **Conditional rendering**: None

## Checks for the Migration

**Files to verify**:
- /opt/myapp-api/.env
- /etc/systemd/system/myapp-api.service
- /etc/logrotate.d/myapp-api
- /usr/local/bin/app-healthcheck.sh
- /usr/local/bin/db-backup.sh

**Service endpoints to check**:
- http://localhost:8000/health

**Templates rendered**:
- app.env.erb → /opt/myapp-api/.env (1 instance)
- app.service.epp → /etc/systemd/system/myapp-api.service (1 instance)
- logrotate.conf.erb → /etc/logrotate.d/myapp-api (1 instance)

## Pre-flight checks:
```bash
# Service status commands
systemctl status myapp-api
curl -f http://localhost:8000/health
ps aux | grep gunicorn

# Configuration validation
ls -la /opt/myapp-api/venv/bin/
sudo -u myapp_app psql -h localhost -d myapp_db -c "SELECT 1;"
```