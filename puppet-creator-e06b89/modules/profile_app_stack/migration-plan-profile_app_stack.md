---
source-path: modules/profile_app_stack
---

# Migration Plan: profile_app_stack

**TLDR**: `profile_app_stack` deploys the `myapp-api` Python application from Git, creates its application user and group, prepares Python packages and a virtual environment, optionally manages local PostgreSQL, renders application and systemd configuration, runs database migrations, configures log rotation and health checks, and enables production-only Prometheus monitoring. Production uses revision `v2.4.1`, a remote PostgreSQL server, and eight workers. Staging uses revision `main`, local PostgreSQL, and one worker. Database passwords and production secret keys are encrypted Puppet values and must be migrated to Ansible Vault or an external secret provider.

## Service Type and Instances

**Service Type**: Python web application managed by systemd, with optional PostgreSQL and Prometheus integration.

**Configured Instances**:

- **Production `myapp-api`**: Production Python API service
  - Repository: `https://github.com/example-org/myapp-api.git`
  - Revision: `v2.4.1`
  - Location/Path: `/opt/myapp-api`
  - User/group: `myapp` / `myapp`
  - Port/Socket: TCP `8000`
  - Database host: `db-primary.prod.internal`
  - Database port: `5432`
  - Database: `myapp_db`
  - Database user: `myapp_app`
  - Workers: `8`
  - Worker class: `uvicorn.workers.UvicornWorker`
  - Maximum requests per worker: `5000`
  - Graceful timeout: `30`
  - Log level: `warning`
  - Log directory: `/var/log/myapp-api`
  - Monitoring: Prometheus node exporter, pushgateway, and metrics cron are enabled when the Puppet `environment` fact is `production`

- **Staging `myapp-api`**: Staging Python API service
  - Repository: `https://github.com/example-org/myapp-api.git`
  - Revision: `main`
  - Location/Path: `/opt/myapp-api`
  - User/group: `myapp` / `myapp`
  - Port/Socket: TCP `8000`
  - Database host: `localhost`
  - Database port: `5432`
  - Database: `myapp_db`
  - Database user: `myapp_app`
  - Workers: `1`
  - Worker class: `uvicorn.workers.UvicornWorker`
  - Maximum requests per worker: `100`
  - Graceful timeout: `30`
  - Log level: `debug`
  - Log directory: `/var/log/myapp-api`
  - Local PostgreSQL: enabled because `db_host == 'localhost'`
  - Monitoring: production-only package and service branches remain disabled

## File Structure

```text
### Manifests

- site/role/manifests/app_stack.pp
- site/profile/manifests/app/stack.pp
- modules/profile_app_stack/manifests/init.pp
- modules/profile_app_stack/manifests/python.pp
- modules/profile_app_stack/manifests/database.pp
- modules/profile_app_stack/manifests/app.pp
- modules/profile_app_stack/manifests/service.pp
- modules/profile_app_stack/manifests/monitoring.pp

### Templates referenced by the execution tree

- profile_app_stack/logrotate.conf.erb
- profile_app_stack/app.env.erb
- profile_app_stack/app.service.epp

### Hiera data

- modules/profile_app_stack/data/common.yaml
- modules/profile_app_stack/data/environment/production.yaml
- modules/profile_app_stack/data/environment/staging.yaml

### Module metadata and Hiera configuration

- modules/profile_app_stack/metadata.json
- modules/profile_app_stack/hiera.yaml
```

## Module Explanation

The module performs operations in the following order:

1. **`role::app_stack`** (`site/role/manifests/app_stack.pp`)
   - Reads `$facts['kernel']` to identify the operating-system kernel.
   - Executes the Linux-only `Exec[None]` conditional when `$facts['kernel'].downcase == 'linux'`.
   - The supplied execution tree does not expose the command, provider, arguments, or idempotence condition for `Exec[None]`; inspect the manifest before implementing the Ansible equivalent.
   - Applies `Class['::profile::base::base']`.
   - Applies `Class['::profile::app::stack']`.
   - Orders `Class['::profile::base::base']` before `Class['::profile::app::stack']`.

2. **`::profile::app::stack`** (`site/profile/manifests/app/stack.pp`)
   - Includes `Class['profile_app_stack']`.
   - Reads `fact('environment')` to identify the Puppet environment used by monitoring conditionals.
   - Runs after `profile::base::base`.

3. **`profile_app_stack`** (`modules/profile_app_stack/manifests/init.pp`)
   - Includes the following classes in dependency order:
     - `Class['profile_app_stack::python']`
     - `Class['profile_app_stack::database']`
     - `Class['profile_app_stack::app']`
     - `Class['profile_app_stack::service']`
     - `Class['profile_app_stack::monitoring']`
   - Orders Python preparation before database management.
   - Orders database management before application deployment.
   - Sends application changes to the service class through `Class['profile_app_stack::app'] ~> Class['profile_app_stack::service']`.
   - Orders the service class before monitoring.
   - The application-to-service relationship provides service refresh behavior after application changes.

4. **`profile_app_stack::python`** (`modules/profile_app_stack/manifests/python.pp`)
   - Installs the package collection derived from `profile_app_stack::python_version = python3`; exact calculated package names require manifest inspection.
   - Creates group `myapp`.
   - Creates user `myapp`.
   - Creates log directory `/var/log/myapp-api`.
   - Renders `/etc/logrotate.d/myapp-api` from `profile_app_stack/logrotate.conf.erb`.
   - The logrotate template has one render and four reported template variables:
     - Application name: `myapp-api`
     - Log directory: `/var/log/myapp-api`
     - Maximum log size: `100M`
     - Rotation count: `7`
   - Preserve the exact ownership, mode, and remaining template implementation details.

5. **`profile_app_stack::database`** (`modules/profile_app_stack/manifests/database.pp`)
   - Evaluates the local PostgreSQL branch using `db_host == 'localhost'`.
   - Production branch:
     - `db_host` is `db-primary.prod.internal`, so the local branch is skipped.
     - The following resources do not run:
       - `package['postgresql', 'postgresql-contrib', 'libpq-dev']`
       - `service['postgresql']`
       - `exec['create_db_user']`
       - `exec['create_database']`
       - `exec['grant_db_privileges']`
   - Staging branch:
     - `db_host` is `localhost`, so the local branch runs.
     - Installs `postgresql`, `postgresql-contrib`, and `libpq-dev`.
     - Manages `service['postgresql']`.
     - Executes `create_db_user`.
     - Executes `create_database`.
     - Executes `grant_db_privileges`.
     - Uses database host `localhost`, port `5432`, database `myapp_db`, user `myapp_app`, and encrypted `profile_app_stack::db_password`.
   - Common resources:
     - Installs package `cron`.
     - Creates `/usr/local/bin/db-backup.sh`.
     - Creates scheduled cron job `database_backup`.
   - Exact commands, guards, command user, service attributes, schedule, arguments, ownership, mode, and environment require inspection of the Puppet manifest.

6. **`profile_app_stack::app`** (`modules/profile_app_stack/manifests/app.pp`)
   - Checks out `https://github.com/example-org/myapp-api.git` into `/opt/myapp-api` using:
     - Production revision `v2.4.1`
     - Staging revision `main`
   - Uses the `vcsrepo` source provider for the Git checkout.
   - Executes `create_app_venv` to create the Python virtual environment.
   - Executes `install_requirements` to install application requirements.
   - Since `pip_packages` is non-empty, installs the following packages into the application virtual environment:
     - `uvicorn`
     - `gunicorn`
     - `psycopg2-binary`
   - Renders `/opt/myapp-api/.env` from `profile_app_stack/app.env.erb`.
   - The environment template has one render and a reported structured count of eight template variables. The manifest data additionally identifies application name, port, directory, database connection values, database password, secret key, and log level; reconcile the exact eight template parameters against the template source before conversion.
   - Preserves the template’s one conditional rendering block.
   - Creates `/usr/local/bin/app-healthcheck.sh`.
   - Executes `run_db_migrations`.
   - Preserve exact commands, guards, ownership, modes, and environment for the virtual-environment, dependency, health-check, and migration resources.
   - Prevent database passwords and secret keys from appearing in Ansible output.

7. **`profile_app_stack::service`** (`modules/profile_app_stack/manifests/service.pp`)
   - Renders `/etc/systemd/system/myapp-api.service` from `profile_app_stack/app.service.epp`.
   - The service template has one render, 11 reported template variables, and two conditional logic blocks.
   - Uses service name `myapp-api`, directory `/opt/myapp-api`, user `myapp`, port `8000`, worker class `uvicorn.workers.UvicornWorker`, and graceful timeout `30`.
   - Uses production values of eight workers, maximum requests `5000`, and log level `warning`.
   - Uses staging values of one worker, maximum requests `100`, and log level `debug`.
   - Executes `app_stack_systemd_daemon_reload`.
   - Manages service `myapp-api`.
   - Application changes notify this class through `Class['profile_app_stack::app'] ~> Class['profile_app_stack::service']`.
   - The supplied execution tree does not expose service refresh behavior, resource-level ordering, or service attributes. Treat daemon reload and restart behavior as an implementation requirement to verify against the manifest, not as fully verified Puppet behavior.

8. **`profile_app_stack::monitoring`** (`modules/profile_app_stack/manifests/monitoring.pp`)
   - Declares virtual resources:
     - `@package 'prometheus-node-exporter'`
     - `@service 'prometheus-node-exporter'`
     - `@package 'prometheus-pushgateway'`
     - `@cron 'push_app_metrics'`
   - Realizes the virtual resources only when `$facts['environment'] == 'production'`.
   - Production resources:
     - Installs `prometheus-node-exporter`.
     - Manages service `prometheus-node-exporter`.
     - Installs `prometheus-pushgateway`.
     - Creates cron job `push_app_metrics`.
   - Common resource:
     - Creates cron job `app_health_check`.
   - Reads `$facts['environment']`.
   - Exact cron schedules and command lines require inspection of the manifest.

## Variables

**Variable Flow Summary**: 35 Hiera definitions represent 23 unique variables across one common/default level and two environment-specific levels. Production and staging override common values through scalar replacement. Hiera values, types, hierarchy behavior, and encryption must be verified against the three Hiera files and `hiera.yaml` during migration.

### Variable Definitions

#### `modules/profile_app_stack/data/common.yaml` (defaults) → Migration note: Base defaults for all nodes

- `profile_app_stack::app_name`: `myapp-api` (type: string)
- `profile_app_stack::app_repo`: `https://github.com/example-org/myapp-api.git` (type: string)
- `profile_app_stack::app_revision`: `main` (type: string)
- `profile_app_stack::app_port`: `8000` (type: integer)
- `profile_app_stack::app_dir`: `/opt/myapp-api` (type: string)
- `profile_app_stack::app_user`: `myapp` (type: string)
- `profile_app_stack::app_group`: `myapp` (type: string)
- `profile_app_stack::python_version`: `python3` (type: string)
- `profile_app_stack::pip_packages`: `['uvicorn', 'gunicorn', 'psycopg2-binary']` (type: array of strings)
- `profile_app_stack::db_host`: `localhost` (type: string)
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::db_name`: `myapp_db` (type: string)
- `profile_app_stack::db_user`: `myapp_app` (type: string)
- `profile_app_stack::db_password`: eyaml-encrypted value (type: string)
- `profile_app_stack::worker_count`: `2` (type: integer)
- `profile_app_stack::worker_class`: `uvicorn.workers.UvicornWorker` (type: string)
- `profile_app_stack::max_requests`: `1000` (type: integer)
- `profile_app_stack::graceful_timeout`: `30` (type: integer)
- `profile_app_stack::log_dir`: `/var/log/myapp-api` (type: string)
- `profile_app_stack::log_level`: `info` (type: string)
- `profile_app_stack::log_max_size`: `100M` (type: string)
- `profile_app_stack::log_rotate_count`: `7` (type: integer)

#### `modules/profile_app_stack/data/environment/production.yaml` (production overrides) → Migration note: Values loaded for production nodes

- `profile_app_stack::app_revision`: `v2.4.1` (type: string)
- `profile_app_stack::worker_count`: `8` (type: integer)
- `profile_app_stack::max_requests`: `5000` (type: integer)
- `profile_app_stack::log_level`: `warning` (type: string)
- `profile_app_stack::db_host`: `db-primary.prod.internal` (type: string)
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::secret_key`: eyaml-encrypted value (type: string)

#### `modules/profile_app_stack/data/environment/staging.yaml` (staging overrides) → Migration note: Values loaded for staging nodes

- `profile_app_stack::app_revision`: `main` (type: string)
- `profile_app_stack::worker_count`: `1` (type: integer)
- `profile_app_stack::max_requests`: `100` (type: integer)
- `profile_app_stack::log_level`: `debug` (type: string)
- `profile_app_stack::db_host`: `localhost` (type: string)
- `profile_app_stack::secret_key`: `staging-not-secret-at-all` (type: string)

### Effective Ansible Variable Sets

#### Production

```yaml
app_name: myapp-api
app_repo: https://github.com/example-org/myapp-api.git
app_revision: v2.4.1
app_port: 8000
app_dir: /opt/myapp-api
app_user: myapp
app_group: myapp
python_version: python3
pip_packages:
  - uvicorn
  - gunicorn
  - psycopg2-binary
db_host: db-primary.prod.internal
db_port: 5432
db_name: myapp_db
db_user: myapp_app
worker_count: 8
worker_class: uvicorn.workers.UvicornWorker
max_requests: 5000
graceful_timeout: 30
log_dir: /var/log/myapp-api
log_level: warning
log_max_size: 100M
log_rotate_count: 7
```

Sensitive production values:

```yaml
db_password: "<Ansible Vault or external-secret value>"
secret_key: "<Ansible Vault or external-secret value>"
```

#### Staging

```yaml
app_name: myapp-api
app_repo: https://github.com/example-org/myapp-api.git
app_revision: main
app_port: 8000
app_dir: /opt/myapp-api
app_user: myapp
app_group: myapp
python_version: python3
pip_packages:
  - uvicorn
  - gunicorn
  - psycopg2-binary
db_host: localhost
db_port: 5432
db_name: myapp_db
db_user: myapp_app
worker_count: 1
worker_class: uvicorn.workers.UvicornWorker
max_requests: 100
graceful_timeout: 30
log_dir: /var/log/myapp-api
log_level: debug
log_max_size: 100M
log_rotate_count: 7
```

Sensitive staging values:

```yaml
db_password: "<Ansible Vault or external-secret value>"
secret_key: "<Ansible Vault or external-secret value>"
```

### Variable Migration Summary

- **Common defaults**: 22 definitions from `common.yaml`
- **Production-specific variables**: 7 definitions from `production.yaml`
- **Staging-specific variables**: 6 definitions from `staging.yaml`
- **Unique variables**: 23 across all three Hiera files
- **Host-specific variables**: none identified
- **Encrypted Puppet values**: 2 values:
  - `profile_app_stack::db_password`
  - Production `profile_app_stack::secret_key`
- **Logical secrets requiring secure Ansible handling**: 2 in every environment:
  - Database password
  - Application secret key

### Cross-Level Overrides

- `profile_app_stack::app_revision`: common, production, and staging; scalar replacement
- `profile_app_stack::worker_count`: common, production, and staging; scalar replacement
- `profile_app_stack::max_requests`: common, production, and staging; scalar replacement
- `profile_app_stack::log_level`: common, production, and staging; scalar replacement
- `profile_app_stack::db_host`: common, production, and staging; scalar replacement
- `profile_app_stack::db_port`: common and production; scalar replacement, with the same effective value `5432`
- `profile_app_stack::secret_key`: production and staging only; no common default
- `profile_app_stack::db_password`: common only; encrypted value

### Merge Strategy Notes

- Scalar overrides use first-value or higher-priority replacement behavior; values are not merged.
- `pip_packages` is defined as a complete common array and has no environment override.
- No hash or deep-merge variables are identified.
- Confirm the effective lookup order and merge settings in `modules/profile_app_stack/hiera.yaml`.

## Dependencies

**External Puppet module dependencies**:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

The supplied execution tree does not show direct resources from the Redis, firewall, concat, or APT modules. Confirm whether omitted manifest details invoke them before adding equivalent Ansible roles.

**System package dependencies**:

- Python package collection derived from `python3`
- `postgresql` — staging/local database branch only
- `postgresql-contrib` — staging/local database branch only
- `libpq-dev` — staging/local database branch only
- `cron`
- `prometheus-node-exporter` — production monitoring branch only
- `prometheus-pushgateway` — production monitoring branch only

**Service dependencies and ordering**:

- Base profile before application profile.
- Python class before database class.
- Database class before application class.
- Application changes notify the service class.
- Service class before monitoring class.
- Daemon reload and service refresh behavior must be verified against `modules/profile_app_stack/manifests/service.pp`; implement reload-before-service-update behavior in Ansible.

## Puppet Facts Used

- `$facts['kernel']`
  - Provides the operating-system kernel name.
  - Used for the Linux-only `Exec[None]` conditional in `site/role/manifests/app_stack.pp`.

- `fact('environment')`
  - Provides the Puppet environment name.
  - Used by `site/profile/manifests/app/stack.pp` and the monitoring logic.

- `$facts['environment']`
  - Provides the Puppet environment name through the facts hash.
  - Controls realization of Prometheus node exporter, Prometheus pushgateway, and `push_app_metrics` in the production branch.

Use explicit Ansible inventory or group variables such as `app_environment: production` and `app_environment: staging` rather than relying solely on gathered facts.

## Template Conversion Notes

### `profile_app_stack/logrotate.conf.erb`

- Destination: `/etc/logrotate.d/myapp-api`
- Render count: 1
- Reported template variable count: 4
- Values:
  - Application name: `myapp-api`
  - Log directory: `/var/log/myapp-api`
  - Maximum log size: `100M`
  - Rotation count: `7`
- Convert to Jinja2.
- Preserve log rotation frequency, compression, post-rotation behavior, ownership, mode, and any other directives from the Puppet template.

### `profile_app_stack/app.env.erb`

- Destination: `/opt/myapp-api/.env`
- Render count: 1
- Reported structured template variable count: 8
- The execution data also identifies application name, application port, application directory, database host, database port, database name, database user, database password, secret key, and log level as values associated with the rendered environment configuration.
- Reconcile the exact eight template parameters against the source template; values used by the manifest are not necessarily direct template parameters.
- Preserve the single conditional rendering block.
- Deploy with restrictive ownership and permissions.
- Use `no_log: true` for tasks handling the rendered secret-bearing file.
- Do not print database passwords, secret keys, or template contents in Ansible output.

### `profile_app_stack/app.service.epp`

- Destination: `/etc/systemd/system/myapp-api.service`
- Render count: 1
- Reported template variable count: 11
- Logic blocks: 2
- Values:
  - Service name: `myapp-api`
  - User: `myapp`
  - Application directory: `/opt/myapp-api`
  - Port: `8000`
  - Worker count: `8` in production or `1` in staging
  - Worker class: `uvicorn.workers.UvicornWorker`
  - Maximum requests: `5000` in production or `100` in staging
  - Graceful timeout: `30`
  - Log level: `warning` in production or `debug` in staging
- Convert EPP syntax and both conditional blocks to Jinja2.
- Notify a systemd daemon-reload handler when the unit changes.
- Verify whether Puppet restarts or only refreshes the service after reload; implement the equivalent behavior after manifest inspection.

## Credentials and Secret Migration

- `profile_app_stack::db_password`
  - Eyaml-encrypted in common Hiera data.
  - Used by database commands and the application `.env` template.
  - Store in Ansible Vault or retrieve through an external secret provider.
- Production `profile_app_stack::secret_key`
  - Eyaml-encrypted in production Hiera data.
  - Store in Ansible Vault or retrieve through an external secret provider.
- Staging `profile_app_stack::secret_key`
  - Current value is plaintext: `staging-not-secret-at-all`.
  - Move it to Vault or an external secret provider before migration.
- Remove any insecure Puppet fallback such as `changeme` from class parameter defaults.
- Use `no_log: true` for database creation, environment-file deployment, and migration tasks that can expose credentials.
- Ensure `/opt/myapp-api/.env` is not world-readable.
- External `puppet-redis` dependency scans identified optional Redis authentication and TLS credential paths. Migrate those only if the dependency is actually instantiated by the control repository.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/app_stack.pp`
- `site/profile/manifests/app/stack.pp`
- `modules/profile_app_stack/manifests/init.pp`
- `modules/profile_app_stack/manifests/python.pp`
- `modules/profile_app_stack/manifests/database.pp`
- `modules/profile_app_stack/manifests/app.pp`
- `modules/profile_app_stack/manifests/service.pp`
- `modules/profile_app_stack/manifests/monitoring.pp`
- `modules/profile_app_stack/data/common.yaml`
- `modules/profile_app_stack/data/environment/production.yaml`
- `modules/profile_app_stack/data/environment/staging.yaml`
- `modules/profile_app_stack/hiera.yaml`
- `modules/profile_app_stack/metadata.json`
- `profile_app_stack/logrotate.conf.erb`
- `profile_app_stack/app.env.erb`
- `profile_app_stack/app.service.epp`

**Service endpoints to check**:

- Production `myapp-api`: TCP port `8000`
- Staging `myapp-api`: TCP port `8000`
- Production PostgreSQL: `db-primary.prod.internal:5432`
- Staging PostgreSQL: `localhost:5432`
- Production Prometheus node exporter service
- Production Prometheus pushgateway service
- Production `push_app_metrics` cron job
- Production and staging `app_health_check` cron jobs

**Paths to check**:

- `/opt/myapp-api`
- `/opt/myapp-api/.env`
- `/var/log/myapp-api`
- `/etc/logrotate.d/myapp-api`
- `/etc/systemd/system/myapp-api.service`
- `/usr/local/bin/app-healthcheck.sh`
- `/usr/local/bin/db-backup.sh`

**Templates rendered**:

- `profile_app_stack/logrotate.conf.erb`: 1 render
- `profile_app_stack/app.env.erb`: 1 render
- `profile_app_stack/app.service.epp`: 1 render

## Pre-flight checks

```bash
# Common checks
uname -s
command -v python3
python3 --version
command -v pip
command -v git
command -v cron
getent passwd myapp
getent group myapp
git ls-remote https://github.com/example-org/myapp-api.git
systemd-analyze verify /etc/systemd/system/myapp-api.service
logrotate -d /etc/logrotate.d/myapp-api

# Production myapp-api checks
git ls-remote https://github.com/example-org/myapp-api.git refs/tags/v2.4.1
nc -zv db-primary.prod.internal 5432
getent hosts db-primary.prod.internal
systemctl is-enabled myapp-api
systemctl is-active myapp-api
ss -ltn '( sport = :8000 )'
test -x /usr/local/bin/app-healthcheck.sh
test -f /usr/local/bin/db-backup.sh
systemctl is-enabled prometheus-node-exporter
systemctl is-active prometheus-node-exporter
systemctl is-enabled prometheus-pushgateway
systemctl is-active prometheus-pushgateway
systemctl list-timers --all | grep -E 'push_app_metrics|app_health_check' || true

# Staging myapp-api checks
git ls-remote https://github.com/example-org/myapp-api.git refs/heads/main
systemctl is-enabled postgresql
systemctl is-active postgresql
nc -zv localhost 5432
sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname = 'myapp_app';"
sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname = 'myapp_db';"
systemctl is-enabled myapp-api
systemctl is-active myapp-api
ss -ltn '( sport = :8000 )'
test -x /usr/local/bin/app-healthcheck.sh
test -f /usr/local/bin/db-backup.sh

# Application checks for both instances
/ usr/local/bin/app-healthcheck.sh
python3 -m venv --help
test ! -r /opt/myapp-api/.env || true
grep -E '^(db_password|secret_key)' /opt/myapp-api/.env >/dev/null && exit 1 || true
```

Run database migrations before starting `myapp-api`. Confirm that secret values do not appear in Ansible output, command output, or logs.