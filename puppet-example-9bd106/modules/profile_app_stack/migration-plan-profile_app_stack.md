---
source-path: modules/profile_app_stack
---

# Migration Plan: profile_app_stack

**TLDR**: `profile_app_stack` provisions a Linux Python application from Git, optionally installs and manages local PostgreSQL, creates a systemd service, configures log rotation and application environment files, runs database backups and migrations, and installs production monitoring resources. The execution chain is `role::app_stack → profile::app::stack → profile_app_stack`, followed by Python prerequisites, database resources, application checkout/configuration, systemd service management, and monitoring. Environment-specific Hiera data affects application revisions, worker settings, logging, database host configuration, and application secrets. Database credentials and application signing keys must be migrated to Ansible Vault or an external secret provider.

## Service Type and Instances

**Service Type**: Linux Python web application with optional local PostgreSQL, systemd supervision, scheduled backups, health checks, and Prometheus monitoring.

**Configured Instances**:

- **Python application**
  - Application name: effective value of `profile_app_stack::app_name`.
  - Repository: effective value of `profile_app_stack::app_repo`.
  - Revision: effective value of `profile_app_stack::app_revision`.
  - Application directory: effective value of `profile_app_stack::app_dir`.
  - Application user: effective value of `profile_app_stack::app_user`.
  - Application group: effective value of `profile_app_stack::app_group`.
  - Virtual environment: `${app_dir}/venv`.
  - Listening port: effective value of `profile_app_stack::app_port`.
  - Worker count: effective common, production, or staging value.
  - Worker class: effective value of `profile_app_stack::worker_class`.
  - Maximum requests: effective common, production, or staging value.
  - Graceful timeout: effective value of `profile_app_stack::graceful_timeout`.
  - Log directory: effective value of `profile_app_stack::log_dir`.
  - Log level: effective common, production, or staging value.
  - Repository provider: Git through Puppet `vcsrepo`.

- **PostgreSQL**
  - Enabled when the effective `profile_app_stack::db_host` equals `localhost`.
  - Package resource: Puppet package resource containing `postgresql` and `postgresql-contrib`.
  - Ansible package implementation: `postgresql`, `postgresql-contrib`.
  - Service: `postgresql`.
  - Database host: effective value of `profile_app_stack::db_host`.
  - Database port: effective value of `profile_app_stack::db_port`.
  - Database name: effective value of `profile_app_stack::db_name`.
  - Database user: effective value of `profile_app_stack::db_user`.
  - Database password: encrypted common Hiera-eyaml value.
  - Backup script: `/usr/local/bin/db-backup.sh`.
  - Backup schedule: defined by the Puppet `database_backup` cron resource; exact schedule is pending source verification.

- **Application systemd service**
  - Unit path: `/etc/systemd/system/${app_name}.service`.
  - Service name: effective `profile_app_stack::app_name`.
  - Application port: effective `profile_app_stack::app_port`.
  - Worker settings: effective worker count, worker class, maximum requests, and graceful timeout.
  - Service template: `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp`.
  - Expected state: enabled and running, subject to confirmation from the original manifest.

- **Application health check**
  - Script: `/usr/local/bin/app-healthcheck.sh`.
  - Cron resource: `app_health_check`.
  - Schedule and command: pending source verification.

- **Prometheus node exporter**
  - Package: `prometheus-node-exporter`.
  - Service: `prometheus-node-exporter`.
  - Production behavior: the package and production monitoring resources are conditional on the Puppet environment being `production`.
  - Resource classification: the structured analysis reports a service resource outside the production conditional and also reports a production-conditional service with the same title. Confirm whether this duplicate is an analysis artifact or an actual duplicate declaration before implementation.

- **Prometheus Pushgateway**
  - Package: `prometheus-pushgateway`.
  - Cron resource: `push_app_metrics`.
  - Production behavior: package and push metrics cron resources are conditional on the Puppet environment being `production`.
  - Schedule, command, user, and environment: pending source verification.

## File Structure

### Manifests

- `site/role/manifests/app_stack.pp`
- `site/profile/manifests/app/stack.pp`
- `site/modules/linux/profile_app_stack/manifests/init.pp`
- `site/modules/linux/profile_app_stack/manifests/python.pp`
- `site/modules/linux/profile_app_stack/manifests/database.pp`
- `site/modules/linux/profile_app_stack/manifests/app.pp`
- `site/modules/linux/profile_app_stack/manifests/service.pp`
- `site/modules/linux/profile_app_stack/manifests/monitoring.pp`

### Templates

- `site/modules/linux/profile_app_stack/templates/profile_app_stack/logrotate.conf.erb`
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.env.erb`
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp`

### Hiera data

- `modules/profile_app_stack/data/common.yaml`
- `modules/profile_app_stack/data/environment/production.yaml`
- `modules/profile_app_stack/data/environment/staging.yaml`

### Custom components

- None detected.

## Module Explanation

The module performs operations in the following order.

1. **`role::app_stack`** (`site/role/manifests/app_stack.pp`)
   - Evaluates the Linux-only condition `$facts['kernel'].downcase == 'linux'`.
   - Includes `::profile::base::base`.
   - Includes `::profile::app::stack`.
   - Preserves the ordering relationship `Class['::profile::base::base'] -> Class['::profile::app::stack']`.
   - The supplied execution data contains an `exec[None]` entry, but does not expose its command or attributes. Reproduce it only after inspecting the original resource definition.

2. **`profile::app::stack`** (`site/profile/manifests/app/stack.pp`)
   - Includes `profile_app_stack`.
   - Delegates application resources to `profile_app_stack`.

3. **`profile_app_stack`** (`site/modules/linux/profile_app_stack/manifests/init.pp`)
   - Includes `profile_app_stack::python`.
   - Includes `profile_app_stack::database`.
   - Includes `profile_app_stack::app`.
   - Includes `profile_app_stack::service`.
   - Includes `profile_app_stack::monitoring`.
   - Orders Python prerequisites before database resources.
   - Orders database resources before application resources.
   - Sends application changes to the service class using `Class['profile_app_stack::app'] ~> Class['profile_app_stack::service']`.
   - Orders the service class before monitoring.
   - Implement application-to-service refresh behavior with Ansible handlers.

4. **`profile_app_stack::python`** (`site/modules/linux/profile_app_stack/manifests/python.pp`)
   - Installs the package collection represented by `$python_packages` with `ensure => present`; literal package names require source verification.
   - Creates the effective application group from `profile_app_stack::app_group`.
   - Creates the effective application user from `profile_app_stack::app_user`.
   - Creates the effective application directory from `profile_app_stack::app_dir`.
   - Sets the application directory owner to the effective application user and group to the effective application group.
   - Creates `${app_dir}/venv` using the effective `profile_app_stack::python_version`.
   - Creates the effective log directory from `profile_app_stack::log_dir`.
   - Renders `site/modules/linux/profile_app_stack/templates/profile_app_stack/logrotate.conf.erb` to `/etc/logrotate.d/${app_name}`.
   - Renders the logrotate template once per host.
   - Passes the four variables required by the original template, including the application name, log directory, log rotation size, and rotation count.

5. **`profile_app_stack::database`** (`site/modules/linux/profile_app_stack/manifests/database.pp`)
   - Evaluates the condition `profile_app_stack::db_host == 'localhost'`.
   - When true, installs the Puppet package collection containing `postgresql` and `postgresql-contrib`.
   - Starts the `postgresql` service; exact enablement and restart attributes require source verification.
   - Creates the effective database user using the encrypted database password.
   - Creates the effective database named by `profile_app_stack::db_name`.
   - Grants database privileges to the effective database user.
   - Creates `/usr/local/bin/db-backup.sh`.
   - Creates the `database_backup` cron resource to run the backup script.
   - Does not install or start PostgreSQL for remote database hosts.
   - Exact commands, guards, ownership, permissions, schedule, and environment require source verification.

6. **`profile_app_stack::app`** (`site/modules/linux/profile_app_stack/manifests/app.pp`)
   - Checks out the effective Git repository into `profile_app_stack::app_dir`.
   - Uses the effective `profile_app_stack::app_revision`.
   - Uses the Git provider implied by Puppet `vcsrepo`.
   - Installs Python requirements into `${app_dir}/venv`.
   - Evaluates the `pip_packages` branch:
     - If `profile_app_stack::pip_packages` is non-empty, installs the listed packages.
     - If it is empty, the branch runs zero times.
   - Renders `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.env.erb` to `${app_dir}/.env`.
   - Renders the application environment template once per host.
   - Uses restrictive ownership and permissions for `.env`.
   - Creates `/usr/local/bin/app-healthcheck.sh`.
   - Runs application database migrations.
   - Preserves ordering after Python and database resources and before service refresh handlers.

7. **`profile_app_stack::service`** (`site/modules/linux/profile_app_stack/manifests/service.pp`)
   - Renders `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp` to `/etc/systemd/system/${app_name}.service`.
   - Renders the systemd unit once per host.
   - Supplies the effective application name, user, group, application directory, virtual environment, port, worker count, worker class, maximum requests, graceful timeout, and logging configuration.
   - Runs the systemd daemon reload operation after the unit changes.
   - Manages the service named by the effective `profile_app_stack::app_name`.
   - Enables and starts the application service when confirmed by the original manifest.
   - Preserves the notification relationship from application changes to the service class.
   - In Ansible, notify a daemon-reload handler when the unit changes and an application restart handler when the unit or relevant application configuration changes.

8. **`profile_app_stack::monitoring`** (`site/modules/linux/profile_app_stack/manifests/monitoring.pp`)
   - Declares virtual resources for:
     - `package['prometheus-node-exporter']`
     - `package['prometheus-pushgateway']`
     - `cron['push_app_metrics']`
   - The structured analysis also reports `service['prometheus-node-exporter']` outside the production conditional and a service resource with the same title inside the production conditional. Confirm the original manifest to determine whether this is a duplicate declaration or analysis artifact.
   - Evaluates the production condition `$facts['environment'] == 'production'`.
   - In production, realizes `prometheus-node-exporter`.
   - In production, realizes `prometheus-pushgateway`.
   - In production, realizes `push_app_metrics`.
   - Manages `app_health_check`.
   - Implements the production condition explicitly in Ansible rather than reproducing Puppet virtual-resource semantics.
   - Ensures monitoring resources are absent from staging unless separately enabled by the source manifest.

## Variables

**Variable Flow Summary**: 22 common Hiera keys are identified in the supplied plan, with production and staging environment data. The supplied structured execution analysis does not independently verify Hiera file contents, types, literal values, encryption status, or override records. Treat the definitions below as migration inventory requiring Hiera-source verification.

### Variable Definitions

#### `modules/profile_app_stack/data/common.yaml` — base defaults for all nodes

- `profile_app_stack::app_name`: value not exposed (type: string) → `app_stack_app_name`
- `profile_app_stack::app_repo`: value not exposed (type: string) → `app_stack_app_repo`
- `profile_app_stack::app_revision`: value not exposed (type: string) → `app_stack_app_revision`
- `profile_app_stack::app_port`: value not exposed (type: integer) → `app_stack_app_port`
- `profile_app_stack::app_dir`: value not exposed (type: string) → `app_stack_app_dir`
- `profile_app_stack::app_user`: value not exposed (type: string) → `app_stack_app_user`
- `profile_app_stack::app_group`: value not exposed (type: string) → `app_stack_app_group`
- `profile_app_stack::db_host`: value not exposed (type: string) → `app_stack_db_host`
- `profile_app_stack::db_port`: value not exposed (type: integer) → `app_stack_db_port`
- `profile_app_stack::db_name`: value not exposed (type: string) → `app_stack_db_name`
- `profile_app_stack::db_user`: value not exposed (type: string) → `app_stack_db_user`
- `profile_app_stack::db_password`: encrypted eyaml value claimed by the supplied plan (type: string) → `vault_app_stack_db_password`
- `profile_app_stack::worker_count`: value not exposed (type: integer) → `app_stack_worker_count`
- `profile_app_stack::worker_class`: value not exposed (type: string) → `app_stack_worker_class`
- `profile_app_stack::max_requests`: value not exposed (type: integer) → `app_stack_max_requests`
- `profile_app_stack::graceful_timeout`: value not exposed (type: integer) → `app_stack_graceful_timeout`
- `profile_app_stack::log_dir`: value not exposed (type: string) → `app_stack_log_dir`
- `profile_app_stack::log_level`: value not exposed (type: string) → `app_stack_log_level`
- `profile_app_stack::python_version`: value not exposed (type: string) → `app_stack_python_version`
- `profile_app_stack::pip_packages`: value not exposed (type: array) → `app_stack_pip_packages`
- `profile_app_stack::log_max_size`: value not exposed (type: string) → `app_stack_log_max_size`
- `profile_app_stack::log_rotate_count`: value not exposed (type: integer) → `app_stack_log_rotate_count`

#### `modules/profile_app_stack/data/environment/production.yaml` — production overrides

- `profile_app_stack::app_revision`: production value, overrides common (type: string) → `app_stack_app_revision`
- `profile_app_stack::worker_count`: production value, overrides common (type: integer) → `app_stack_worker_count`
- `profile_app_stack::max_requests`: production value, overrides common (type: integer) → `app_stack_max_requests`
- `profile_app_stack::log_level`: production value, overrides common (type: string) → `app_stack_log_level`
- `profile_app_stack::db_host`: production value, overrides common (type: string) → `app_stack_db_host`
- `profile_app_stack::db_port`: repeats the common effective value (type: integer) → `app_stack_db_port`
- `profile_app_stack::secret_key`: encrypted production secret claimed by the supplied plan (type: string) → `vault_app_stack_secret_key`

#### `modules/profile_app_stack/data/environment/staging.yaml` — staging overrides

- `profile_app_stack::app_revision`: repeats the common effective value (type: string) → `app_stack_app_revision`
- `profile_app_stack::worker_count`: staging value, overrides common (type: integer) → `app_stack_worker_count`
- `profile_app_stack::max_requests`: staging value, overrides common (type: integer) → `app_stack_max_requests`
- `profile_app_stack::log_level`: staging value, overrides common (type: string) → `app_stack_log_level`
- `profile_app_stack::db_host`: repeats the common effective value (type: string) → `app_stack_db_host`
- `profile_app_stack::secret_key`: plaintext staging value claimed by the supplied plan (type: string) → `vault_app_stack_secret_key`

### Variable Migration Summary

- **Common defaults**: 22 variables claimed by the supplied Hiera inventory; verify against the source files.
- **Production-specific entries**: 7 entries claimed by the supplied Hiera inventory.
- **Staging-specific entries**: 6 entries claimed by the supplied Hiera inventory.
- **Environment-specific variables**: application revision, worker count, maximum requests, log level, database host, database port, and secret key.
- **Encrypted variables**: database password and production application secret key, subject to source verification.
- **Potentially unused or template-only variables**: `log_dir`, `log_level`, `python_version`, `pip_packages`, `log_max_size`, and `log_rotate_count`. Six variables are listed; confirm usage against the original manifests and templates.
- **Secrets without a common fallback**: `profile_app_stack::secret_key` is claimed to be defined only in production and staging.

### Cross-Level Overrides

- `app_revision`: common and production; production takes precedence. Staging repeats common.
- `worker_count`: common, production, and staging; environment value takes precedence.
- `max_requests`: common, production, and staging; environment value takes precedence.
- `log_level`: common, production, and staging; environment value takes precedence.
- `db_host`: common, production, and staging; production overrides common, while staging repeats common.
- `db_port`: common and production; production repeats the common value.
- `secret_key`: separate production and staging values with no common fallback identified.
- `db_password`: common encrypted value only.

### Merge Strategy Notes

- Environment-level overrides use first-value precedence, with higher-priority environment data winning.
- No hash merge behavior is indicated.
- No deep merge behavior is indicated.
- Verify the Hiera hierarchy and merge settings before implementation.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.7.0` — version claim requires dependency-source verification.
- `puppetlabs-concat` `9.0.2` — version claim requires dependency-source verification.
- `puppetlabs-firewall` `8.1.3` — version claim requires dependency-source verification.
- `puppetlabs-vcsrepo` `6.1.0` — directly represented by `vcsrepo[$app_dir]`; version requires dependency-source verification.
- `puppet-redis` `11.0.0` — version claim requires dependency-source verification.
- `puppetlabs-apt` `9.4.0` — version claim requires dependency-source verification.

Only `puppetlabs-vcsrepo` is directly represented in the supplied execution tree.

**System package dependencies**:

- Package collection represented by `$python_packages`; literal names require source verification.
- `postgresql`
- `postgresql-contrib`
- `prometheus-node-exporter` in production
- `prometheus-pushgateway` in production

**Service dependencies**:

- `Class['::profile::base::base'] -> Class['::profile::app::stack']`
- `Class['profile_app_stack::python'] -> Class['profile_app_stack::database']`
- `Class['profile_app_stack::database'] -> Class['profile_app_stack::app']`
- `Class['profile_app_stack::app'] ~> Class['profile_app_stack::service']`
- `Class['profile_app_stack::service'] -> Class['profile_app_stack::monitoring']`

## Puppet Facts Used

- `$facts['kernel']`
  - Identifies the operating-system kernel.
  - Restricts `role::app_stack` execution to Linux hosts when `.downcase == 'linux'`.
- `$facts['environment']`
  - Identifies the Puppet environment.
  - Realizes production monitoring resources when the value is `production`.

## Template Conversion Notes

### `site/modules/linux/profile_app_stack/templates/profile_app_stack/logrotate.conf.erb`

- Destination: `/etc/logrotate.d/${app_name}`.
- Render count: once per host.
- Four template variables are referenced.
- Expected inputs include the application name, log directory, maximum log size, and rotation count.
- Preserve the original rotation directives, compression behavior, postrotate commands, and file matching logic after inspecting the source template.
- Use restrictive permissions appropriate for a logrotate configuration.

### `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.env.erb`

- Destination: `${app_dir}/.env`.
- Render count: once per host.
- Eight template variables are referenced.
- One logic block is present.
- Expected inputs include application, database, logging, database password, and application secret-key settings.
- Use restrictive ownership and mode.
- Use `no_log: true` for tasks that may expose the database password or application secret.
- Verify the claimed insecure `changeme` fallback against the original manifest before migration; do not carry it into Ansible.

### `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp`

- Destination: `/etc/systemd/system/${app_name}.service`.
- Render count: once per host.
- Twelve template variables are referenced.
- Two logic blocks are present.
- Preserve conditional command-line arguments and environment handling.
- Include the effective application name, user, group, application directory, virtual environment, port, worker count, worker class, maximum requests, graceful timeout, log directory, and log level.
- Notify a systemd daemon reload when the unit changes.
- Notify an application restart when the unit or relevant application configuration changes.

## Credentials and Secret Handling

- **`profile_app_stack::db_password`**
  - Claimed to be encrypted with Hiera-eyaml in `modules/profile_app_stack/data/common.yaml`.
  - Map to `vault_app_stack_db_password` or an external secret provider.
  - Do not expose it in command output, logs, templates, or Ansible results.

- **`profile_app_stack::secret_key`**
  - Claimed to be encrypted in production Hiera data.
  - Claimed to be plaintext in staging Hiera data.
  - Migrate both environments to protected secret storage.
  - Fail deployment if the secret is undefined.
  - Verify the claimed `changeme` manifest fallback against the original manifest and do not preserve an insecure fallback.

- **Redis-related parameters**
  - `$redis::masterauth`
  - `$redis::requirepass`
  - `$redis::sentinel::auth_pass`
  - `$redis::sentinel::requirepass`
  - Redis TLS key, certificate, and CA paths
  - These were reported by broader dependency analysis but are not present in the supplied module execution tree. Verify whether they belong to this migration before mapping them.

- **`concat::fragment` sensitive values**
  - `concat::fragment` is reported to accept `Sensitive[String]`, but no direct concat resource appears in this module tree.
  - Verify broader repository usage before migrating.

- Mark secret-consuming Ansible tasks with `no_log: true`.
- Render `.env`, backup configuration, and other secret-bearing files with restrictive ownership and mode.
- Avoid logging commands containing database passwords.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/app_stack.pp`
- `site/profile/manifests/app/stack.pp`
- `site/modules/linux/profile_app_stack/manifests/init.pp`
- `site/modules/linux/profile_app_stack/manifests/python.pp`
- `site/modules/linux/profile_app_stack/manifests/database.pp`
- `site/modules/linux/profile_app_stack/manifests/app.pp`
- `site/modules/linux/profile_app_stack/manifests/service.pp`
- `site/modules/linux/profile_app_stack/manifests/monitoring.pp`
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/logrotate.conf.erb`
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.env.erb`
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp`
- `modules/profile_app_stack/data/common.yaml`
- `modules/profile_app_stack/data/environment/production.yaml`
- `modules/profile_app_stack/data/environment/staging.yaml`

**Service endpoints to check**:

- **Python application**: effective `profile_app_stack::app_port`.
- **PostgreSQL**: effective `profile_app_stack::db_port`, only when `profile_app_stack::db_host == 'localhost'`.
- **Application systemd service**: effective `profile_app_stack::app_name`.
- **Prometheus node exporter**: exporter endpoint when production installation is enabled.
- **Prometheus Pushgateway**: Pushgateway endpoint when production installation is enabled.

**Templates rendered**:

- `site/modules/linux/profile_app_stack/templates/profile_app_stack/logrotate.conf.erb` — once per host.
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.env.erb` — once per host.
- `site/modules/linux/profile_app_stack/templates/profile_app_stack/app.service.epp` — once per host.

## Pre-flight checks

```bash
# Confirm the host is Linux
uname -s

# Confirm the effective deployment environment
echo "$DEPLOYMENT_ENVIRONMENT"

# Confirm the application repository and revision are reachable
git ls-remote "$APP_REPO" "$APP_REVISION"

# Confirm the application user and group
getent passwd "$APP_USER"
getent group "$APP_GROUP"

# Confirm the configured Python interpreter
"$PYTHON_BIN" --version

# Confirm the application virtual environment can be created
test -x "$APP_DIR/venv/bin/python"

# Python application checks
test -d "$APP_DIR"
test -d "$APP_DIR/venv"
test -x "$APP_DIR/venv/bin/python"
curl --fail "http://127.0.0.1:${APP_PORT}/"

# Application systemd service checks
systemd-analyze verify "/etc/systemd/system/${APP_NAME}.service"
systemctl daemon-reload
systemctl is-enabled "$APP_NAME"
systemctl is-active "$APP_NAME"

# PostgreSQL instance checks when DB_HOST is localhost
systemctl is-active postgresql
pg_isready --host "$DB_HOST" --port "$DB_PORT" --dbname "$DB_NAME" --username "$DB_USER"
test -x /usr/local/bin/db-backup.sh
/usr/local/bin/db-backup.sh --help

# Application health-check instance
test -x /usr/local/bin/app-healthcheck.sh
/usr/local/bin/app-healthcheck.sh

# Prometheus node exporter checks in production
dpkg-query -W prometheus-node-exporter 2>/dev/null || rpm -q prometheus-node-exporter
systemctl is-active prometheus-node-exporter

# Prometheus Pushgateway checks in production
dpkg-query -W prometheus-pushgateway 2>/dev/null || rpm -q prometheus-pushgateway
curl --fail http://127.0.0.1:9091/-/healthy

# Validate logrotate configuration
logrotate -d "/etc/logrotate.d/${APP_NAME}"

# Confirm secret-bearing files exist with restrictive permissions
stat -c '%a %U %G %n' "$APP_DIR/.env" /usr/local/bin/db-backup.sh

# Confirm production-only resources are absent from staging and present in production
```
