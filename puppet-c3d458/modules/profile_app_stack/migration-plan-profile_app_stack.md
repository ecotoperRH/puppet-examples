---
source-path: modules/profile_app_stack
---

# Migration Plan: profile_app_stack

**TLDR**: `profile_app_stack` deploys a Python application from Git, creates its runtime user and group, prepares a virtual environment, installs dependencies, optionally manages local PostgreSQL resources, renders application environment and systemd unit files, runs database migrations, configures log rotation and health checks, schedules database backups and application health checks, and declares optional virtual Prometheus resources. The execution chain and resource relationships are confirmed, while Hiera literal values, the complete 62-file analysis inventory, template filesystem locations, custom-component analysis, and PuppetDB analysis require verification from the source repository. Secrets must be migrated to Ansible Vault or an external secret manager.

## Service Type and Instances

**Service Type**: Python application service with optional local PostgreSQL, systemd supervision, cron jobs, and optional Prometheus monitoring integration.

**Configured Instances**:

- **Python application**
  - Service name: effective `profile_app_stack::app_name`; literal value requires verification.
  - Repository: effective `profile_app_stack::app_repo`; literal value requires verification.
  - Revision:
    - Common source-plan value: `main`.
    - Production source-plan value: `v2.4.1`.
    - Staging source-plan value: `main`.
    - Confirm environment values from authoritative Hiera data.
  - Application directory: effective `profile_app_stack::app_dir`; literal value requires verification.
  - Application user: effective `profile_app_stack::app_user`; literal value requires verification.
  - Application group: effective `profile_app_stack::app_group`; literal value requires verification.
  - Port: effective `profile_app_stack::app_port`; literal value requires verification.
  - Worker count:
    - Common source-plan value: `2`.
    - Production source-plan value: `8`.
    - Staging source-plan value: `1`.
  - Worker class: effective `profile_app_stack::worker_class`; literal value requires verification.
  - Maximum requests:
    - Common source-plan value: `1000`.
    - Production source-plan value: `5000`.
    - Staging source-plan value: `100`.
  - Graceful timeout: effective `profile_app_stack::graceful_timeout`; literal value requires verification.
  - Log level:
    - Common source-plan value: `info`.
    - Production source-plan value: `warning`.
    - Staging source-plan value: `debug`.

- **Database**
  - Database host:
    - Local PostgreSQL resources are declared only when the effective host equals `localhost`.
    - Source-plan values report `localhost` for common and staging and `db-primary.prod.internal` for production; confirm these values from Hiera.
  - Database port: effective `profile_app_stack::db_port`; source-plan value is `5432` for common, production, and inherited staging configuration.
  - Database name: effective `profile_app_stack::db_name`; literal value requires verification.
  - Database user: effective `profile_app_stack::db_user`; literal value requires verification.
  - Database password: encrypted common Hiera value; literal value is unavailable.
  - Local PostgreSQL packages and service are installed only when `app_stack_db_host == 'localhost'`.

- **Monitoring**
  - Virtual package: `prometheus-node-exporter`.
  - Virtual service: `prometheus-node-exporter`.
  - Virtual package: `prometheus-pushgateway`.
  - Virtual cron resource: `push_app_metrics`.
  - These resources are declared generally and again inside the production conditional. They become active only if realized elsewhere and must be represented in Ansible by an explicit opt-in feature variable.
  - Application health-check cron resource: `app_health_check`.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
### Manifests

- modules/profile_app_stack/manifests/init.pp
- modules/profile_app_stack/manifests/python.pp
- modules/profile_app_stack/manifests/database.pp
- modules/profile_app_stack/manifests/app.pp
- modules/profile_app_stack/manifests/service.pp
- modules/profile_app_stack/manifests/monitoring.pp
- site/profile/manifests/app/stack.pp
- site/role/manifests/app_stack.pp

### Templates referenced by the execution tree

- profile_app_stack/logrotate.conf.erb
- profile_app_stack/app.env.erb
- profile_app_stack/app.service.epp

### Data files

- modules/profile_app_stack/data/common.yaml
- modules/profile_app_stack/data/environment/production.yaml
- modules/profile_app_stack/data/environment/staging.yaml

### Custom components

- No custom types reported.
- No custom providers reported.
- No custom facts reported.
- No custom functions reported.
```

The execution summary confirms the logical template names and render metadata. Verify their physical filesystem paths separately.

## Module Explanation

The module executes in this order:

1. **`role::app_stack`** (`site/role/manifests/app_stack.pp`)
   - Evaluates `$facts['kernel'].downcase == 'linux'`.
   - Declares the Linux-only `exec[None]` resource when the condition is true.
   - The supplied analysis does not include the command, path, refresh behavior, or exit status; obtain these from the manifest before implementation.
   - Includes `::profile::base::base` before `::profile::app::stack`.
   - Orders `Class['::profile::base::base']` before `Class['::profile::app::stack']`.

2. **`::profile::app::stack`** (`site/profile/manifests/app/stack.pp`)
   - Includes `profile_app_stack`.
   - Uses `fact('environment')` for production-only monitoring behavior through `$facts['environment']`.

3. **`profile_app_stack`** (`modules/profile_app_stack/manifests/init.pp`)
   - Defines module parameters and Hiera lookups.
   - Includes, in order:
     - `profile_app_stack::python`
     - `profile_app_stack::database`
     - `profile_app_stack::app`
     - `profile_app_stack::service`
     - `profile_app_stack::monitoring`
   - Orders `Class['profile_app_stack::python']` before `Class['profile_app_stack::database']`.
   - Orders `Class['profile_app_stack::database']` before `Class['profile_app_stack::app']`.
   - Notifies `Class['profile_app_stack::service']` from `Class['profile_app_stack::app']`.
   - Orders `Class['profile_app_stack::service']` before `Class['profile_app_stack::monitoring']`.

4. **`profile_app_stack::python`** (`modules/profile_app_stack/manifests/python.pp`)
   - Computes the Python package list from `python_version`; exact package names and ensure values require verification.
   - Manages the effective application group through `group[$profile_app_stack::app_group]`.
   - Manages the effective application user through `user[$profile_app_stack::app_user]`.
   - Creates the effective log directory through `file[$profile_app_stack::log_dir]`.
   - Deploys `/etc/logrotate.d/<effective app_name>` through `file[/etc/logrotate.d/${profile_app_stack::app_name}]`.
   - Renders `profile_app_stack/logrotate.conf.erb` once per host.
   - Preserves the source template’s four variables, log rotation directives, ownership, mode, and any postrotate behavior.

5. **`profile_app_stack::database`** (`modules/profile_app_stack/manifests/database.pp`)
   - When the effective database host equals `localhost`, manages:
     - `package[postgresql]`
     - `package[postgresql-contrib]`
     - `package[libpq-dev]`
     - `service[postgresql]`
     - `exec[create_db_user]`
     - `exec[create_database]`
     - `exec[grant_db_privileges]`
   - Creates the configured database user using the effective `db_user` and encrypted `db_password`.
   - Creates the configured database using the effective `db_name`.
   - Grants database privileges to the effective `db_user`.
   - Exact commands, guards, privileges, ownership, and package ensure values require verification. Prefer `community.postgresql` modules over shell commands.
   - Regardless of database location, manages:
     - `package[cron]`
     - `/usr/local/bin/db-backup.sh`
     - `cron[database_backup]`
   - Deploys `/usr/local/bin/db-backup.sh` before enabling `database_backup`.
   - Preserves the source backup command, schedule, user, environment, ownership, group, and mode.

6. **`profile_app_stack::app`** (`modules/profile_app_stack/manifests/app.pp`)
   - Checks out the application through `vcsrepo[$profile_app_stack::app_dir]`.
   - Uses the effective repository and revision.
   - The Puppet provider is supplied by `puppetlabs-vcsrepo`; provider, owner, group, and update behavior require verification.
   - Creates the Python virtual environment through `exec[create_app_venv]` under the application directory.
   - Uses the effective Python version or the exact executable from the Puppet manifest.
   - Installs requirements through `exec[install_requirements]` after repository checkout and virtual-environment creation.
   - When `pip_packages` is non-empty, installs the effective package list in the virtual environment. When empty, this branch runs zero times.
   - Deploys `<effective app_dir>/.env` through `file[${profile_app_stack::app_dir}/.env]`.
   - Renders `profile_app_stack/app.env.erb` once per host.
   - Preserves the template’s eight variables and one Ruby logic block.
   - Deploys `/usr/local/bin/app-healthcheck.sh` before `cron[app_health_check]`.
   - Runs `exec[run_db_migrations]` after checkout, virtual-environment creation, dependency installation, and `.env` deployment.
   - Uses the application user, working directory, environment, and exact migration command from the Puppet manifest.

7. **`profile_app_stack::service`** (`modules/profile_app_stack/manifests/service.pp`)
   - Deploys `/etc/systemd/system/<effective app_name>.service` through `file[/etc/systemd/system/${profile_app_stack::app_name}.service]`.
   - Renders `profile_app_stack/app.service.epp` once per host.
   - Preserves the template’s twelve variables and two EPP logic blocks.
   - Manages `exec[app_stack_systemd_daemon_reload]` after the unit changes.
   - Manages `service[$profile_app_stack::app_name]` and preserves its enabled, running, restart, and notification behavior.
   - Uses a systemd daemon-reload handler notified by the unit-file task.
   - Application changes notify the service through the class-level `app ~> service` relationship.

8. **`profile_app_stack::monitoring`** (`modules/profile_app_stack/manifests/monitoring.pp`)
   - Declares virtual resources:
     - `@package[prometheus-node-exporter]`
     - `@service[prometheus-node-exporter]`
     - `@package[prometheus-pushgateway]`
     - `@cron[push_app_metrics]`
   - Declares the same four virtual resources inside the production conditional when `$facts['environment'] == 'production'`.
   - Does not install these resources unconditionally in Ansible; expose an explicit `app_stack_monitoring_enabled` feature variable.
   - Manages `cron[app_health_check]`.
   - Uses `$facts['environment']` to control the production-only virtual declarations.

No `.each` loops were identified in the supplied execution tree. No loop expansion is therefore required.

## Variables

**Variable Flow Summary**: 23 module variables are identified: 22 common-level definitions plus `secret_key`, which is absent from common data. The source plan reports seven production overrides and six staging overrides, but these counts and literal Hiera values require confirmation against authoritative Hiera analysis. Environment values use first-value priority over common defaults; no hash or deep merge was reported.

### Variable Definitions

#### `common.yaml` (defaults) → Migration note: base defaults for all nodes

- `profile_app_stack::app_name`: (type: string; literal value requires verification)
- `profile_app_stack::app_repo`: (type: string; literal value requires verification)
- `profile_app_stack::app_revision`: `main` (type: string; source-plan value requires verification)
- `profile_app_stack::app_port`: (type: integer; literal value requires verification)
- `profile_app_stack::app_dir`: (type: string; literal value requires verification)
- `profile_app_stack::app_user`: (type: string; literal value requires verification)
- `profile_app_stack::app_group`: (type: string; literal value requires verification)
- `profile_app_stack::db_host`: `localhost` (type: string; source-plan value requires verification)
- `profile_app_stack::db_port`: `5432` (type: integer; source-plan value requires verification)
- `profile_app_stack::db_name`: (type: string; literal value requires verification)
- `profile_app_stack::db_user`: (type: string; literal value requires verification)
- `profile_app_stack::db_password`: `[ENCRYPTED]` (type: string; encrypted)
- `profile_app_stack::worker_count`: `2` (type: integer; source-plan value requires verification)
- `profile_app_stack::worker_class`: (type: string; literal value requires verification)
- `profile_app_stack::max_requests`: `1000` (type: integer; source-plan value requires verification)
- `profile_app_stack::graceful_timeout`: (type: integer; literal value requires verification)
- `profile_app_stack::log_dir`: (type: string; literal value requires verification)
- `profile_app_stack::log_level`: `info` (type: string; source-plan value requires verification)
- `profile_app_stack::python_version`: (type: string; literal value requires verification)
- `profile_app_stack::pip_packages`: (type: array; contents require verification)
- `profile_app_stack::log_max_size`: (type: string; literal value requires verification)
- `profile_app_stack::log_rotate_count`: (type: integer; literal value requires verification)
- `profile_app_stack::secret_key`: undefined at common level

#### `environment/production.yaml` (production overrides) → Migration note: production-specific values loaded conditionally by environment

- `profile_app_stack::app_revision`: `v2.4.1` (type: string)
- `profile_app_stack::worker_count`: `8` (type: integer)
- `profile_app_stack::max_requests`: `5000` (type: integer)
- `profile_app_stack::log_level`: `warning` (type: string)
- `profile_app_stack::db_host`: `db-primary.prod.internal` (type: string)
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::secret_key`: `[ENCRYPTED]` (type: string; encrypted)

Production inherits common values, including encrypted `db_password`. Confirm all values from Hiera before implementation.

#### `environment/staging.yaml` (staging overrides) → Migration note: staging-specific values loaded conditionally by environment

- `profile_app_stack::app_revision`: `main` (type: string)
- `profile_app_stack::worker_count`: `1` (type: integer)
- `profile_app_stack::max_requests`: `100` (type: integer)
- `profile_app_stack::log_level`: `debug` (type: string)
- `profile_app_stack::db_host`: `localhost` (type: string)
- `profile_app_stack::secret_key`: plaintext source value requiring migration to Vault (type: string)

Staging inherits `db_port: 5432`, all other common defaults, and encrypted common `db_password`.

### Ansible Variable Mapping

Use role variables with the `app_stack_` prefix:

- `app_name` → `app_stack_app_name`
- `app_repo` → `app_stack_app_repo`
- `app_revision` → `app_stack_app_revision`
- `app_port` → `app_stack_app_port`
- `app_dir` → `app_stack_app_dir`
- `app_user` → `app_stack_app_user`
- `app_group` → `app_stack_app_group`
- `db_host` → `app_stack_db_host`
- `db_port` → `app_stack_db_port`
- `db_name` → `app_stack_db_name`
- `db_user` → `app_stack_db_user`
- `db_password` → `app_stack_db_password`, preferably sourced from `vault_app_stack_db_password`
- `worker_count` → `app_stack_worker_count`
- `worker_class` → `app_stack_worker_class`
- `max_requests` → `app_stack_max_requests`
- `graceful_timeout` → `app_stack_graceful_timeout`
- `log_dir` → `app_stack_log_dir`
- `log_level` → `app_stack_log_level`
- `python_version` → `app_stack_python_version`
- `pip_packages` → `app_stack_pip_packages`
- `log_max_size` → `app_stack_log_max_size`
- `log_rotate_count` → `app_stack_log_rotate_count`
- `secret_key` → `app_stack_secret_key`, sourced from an encrypted variable

### Variable Migration Summary

- **Common defaults**: 22 defined variables from `common.yaml`; `secret_key` is absent at this level.
- **Production overrides**: 7 source-plan variables; confirm count against authoritative Hiera analysis.
- **Staging overrides**: 6 source-plan variables; confirm count against authoritative Hiera analysis.
- **Environment-specific variables**: 7 production overrides and 6 staging overrides.
- **Encrypted variables**: 2 known secret values: common `db_password` and production `secret_key`.
- **Plaintext sensitive values requiring migration**: staging `secret_key`.
- **Unresolved values requiring source verification**: `app_name`, `app_repo`, `app_port`, `app_dir`, `app_user`, `app_group`, `db_name`, `db_user`, `worker_class`, `graceful_timeout`, `log_dir`, `python_version`, `pip_packages`, `log_max_size`, and `log_rotate_count`.

### Cross-Level Overrides

- `app_revision`: common, production, and staging; merge strategy: first-value priority.
- `worker_count`: common, production, and staging; merge strategy: first-value priority.
- `max_requests`: common, production, and staging; merge strategy: first-value priority.
- `log_level`: common, production, and staging; merge strategy: first-value priority.
- `db_host`: common, production, and staging; merge strategy: first-value priority.
- `db_port`: common and production, with staging inheriting common; merge strategy: first-value priority.
- `secret_key`: absent from common, production, and staging; merge strategy: first-value priority.
- `db_password`: common encrypted value inherited by production and staging.

### Merge Strategy Notes

- Variables using `hash` merge: none identified.
- Variables using `deep` merge: none identified.
- Variables using `first` priority: all reported environment overrides.
- The source plan reports ordinary Hiera priority behavior rather than hash or deep merging.

## Dependencies

**External Puppet module dependencies**:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

The supplied execution tree does not show resources from `concat`, `firewall`, `redis`, or `apt`. Confirm whether they are used by omitted classes, including `profile::base::base`, before removing them.

**System package dependencies**:

- Python package list derived from `python_version`; exact package names require verification.
- `postgresql`
- `postgresql-contrib`
- `libpq-dev`
- `cron`
- `prometheus-node-exporter` when monitoring is explicitly enabled.
- `prometheus-pushgateway` when monitoring is explicitly enabled.

**Ansible collection dependencies**:

- `community.postgresql`
- `ansible.posix` if selected for cron or filesystem tasks.
- `community.general` only if required by the selected implementation.

**Service dependencies**:

- `::profile::base::base` precedes `::profile::app::stack`.
- Python preparation precedes database setup.
- Database setup precedes application deployment.
- Application changes notify the application service.
- Application service precedes monitoring declarations.
- Systemd daemon reload follows unit deployment and precedes service restart or start.
- Database migrations follow checkout, virtual-environment creation, dependency installation, and `.env` deployment.

## Puppet Facts Used

- `$facts['kernel']`
  - Identifies the operating-system kernel.
  - The top-level Linux-only `exec` is declared when the lowercased value is `linux`.
  - Ansible equivalent: `ansible_facts.kernel`.

- `$facts['environment']`
  - Identifies the Puppet environment.
  - Production controls the additional virtual Prometheus declarations.
  - Ansible equivalent: a consistently populated `app_stack_environment` inventory or group variable.

## Template Conversion Notes

### `profile_app_stack/logrotate.conf.erb`

- Destination: `/etc/logrotate.d/<effective app_name>`.
- Render count: once per host.
- Variables: 4.
- Preserve the effective log directory, application name, maximum log size, rotation count, exact Ruby logic, directives, ownership, mode, and postrotate behavior.
- Physical template path requires verification.

### `profile_app_stack/app.env.erb`

- Destination: `<effective app_dir>/.env`.
- Render count: once per host.
- Variables: 8.
- Logic blocks: 1.
- Preserve exact conditional rendering and variable names.
- Expected content includes database settings, application port or host settings, logging configuration, and the application secret, subject to source-template confirmation.
- Use restrictive permissions and `no_log: true` for secret-bearing tasks.
- Physical template path requires verification.

### `profile_app_stack/app.service.epp`

- Destination: `/etc/systemd/system/<effective app_name>.service`.
- Render count: once per host.
- Variables: 12.
- Logic blocks: 2.
- Preserve service identity, user, group, working directory, virtualenv executable, worker count, worker class, application port, request limits, timeout settings, environment file handling, restart policy, and log handling.
- Notify a daemon-reload handler and restart the application service when the unit changes.
- Physical template path requires verification.

## PuppetDB Dependencies

The supplied execution summary contains no confirmed PuppetDB analysis. No PuppetDB queries, exported resources, or resource collectors were identified in the execution tree. Verify the complete repository before finalizing this conclusion.

Monitoring resources are virtual Puppet resources, not PuppetDB-exported resources. Model their activation with an explicit Ansible variable such as `app_stack_monitoring_enabled`.

## Credentials and Sensitive Data

- `profile_app_stack::db_password`
  - Encrypted in common Hiera.
  - Migrate to `vault_app_stack_db_password` or an external secret manager.
  - Use `no_log: true` for database user creation and `.env` rendering.

- `profile_app_stack::secret_key`
  - Encrypted in production.
  - Plaintext in staging.
  - The Puppet class has an insecure `changeme` fallback.
  - Do not migrate the fallback.
  - Make `app_stack_secret_key` mandatory and fail preflight when undefined.
  - Migrate staging data to a Vault variable such as `vault_app_stack_staging_secret_key`.

- Redis-related sensitive parameters detected in dependency analysis:
  - `redis::masterauth`
  - `redis::instance::masterauth`
  - `redis::requirepass`
  - `redis::instance::requirepass`
  - `redis::sentinel::auth_pass`
  - `redis::sentinel::requirepass`
  - `redis::tls_key_file`
  - `redis::instance::tls_key_file`
  - `redis::sentinel::tls_key_file`

No configured Redis values were supplied for this module. If Redis is required by omitted control-repository classes, migrate those values separately to Vault or an external secret manager.

## Checks for the Migration

**Files to verify**:

- `modules/profile_app_stack/manifests/init.pp`
- `modules/profile_app_stack/manifests/python.pp`
- `modules/profile_app_stack/manifests/database.pp`
- `modules/profile_app_stack/manifests/app.pp`
- `modules/profile_app_stack/manifests/service.pp`
- `modules/profile_app_stack/manifests/monitoring.pp`
- `site/profile/manifests/app/stack.pp`
- `site/role/manifests/app_stack.pp`
- `modules/profile_app_stack/data/common.yaml`
- `modules/profile_app_stack/data/environment/production.yaml`
- `modules/profile_app_stack/data/environment/staging.yaml`
- `profile_app_stack/logrotate.conf.erb`
- `profile_app_stack/app.env.erb`
- `profile_app_stack/app.service.epp`

Also obtain the complete inventory for the reported 62 analyzed files and classify files outside the execution tree as dependencies or out of scope.

**Service endpoints to check**:

- Python application service: effective `app_stack_app_name`.
- Application endpoint: effective `app_stack_app_port`.
- Local database endpoint: `localhost:5432` when `app_stack_db_host == 'localhost'`.
- Production database endpoint: source-plan value `db-primary.prod.internal:5432`; confirm before deployment.
- PostgreSQL service: `postgresql` when local database management is enabled.
- Prometheus services: `prometheus-node-exporter` and `prometheus-pushgateway` only when monitoring is explicitly enabled.

**Templates rendered**:

- `profile_app_stack/logrotate.conf.erb`: once per host.
- `profile_app_stack/app.env.erb`: once per host.
- `profile_app_stack/app.service.epp`: once per host.

## Pre-flight checks

```bash
# Confirm Linux and required facts
test "$(uname -s)" = "Linux"

# Confirm required Ansible variables are defined without printing secrets
ansible-inventory --host "$TARGET_HOST"
ansible "$TARGET_HOST" -m ansible.builtin.assert \
  -a "that=['app_stack_app_name is defined',
            'app_stack_app_repo is defined',
            'app_stack_app_revision is defined',
            'app_stack_app_port is defined',
            'app_stack_app_dir is defined',
            'app_stack_app_user is defined',
            'app_stack_app_group is defined',
            'app_stack_db_host is defined',
            'app_stack_db_port is defined',
            'app_stack_db_name is defined',
            'app_stack_db_user is defined',
            'app_stack_db_password is defined',
            'app_stack_worker_count is defined',
            'app_stack_worker_class is defined',
            'app_stack_max_requests is defined',
            'app_stack_graceful_timeout is defined',
            'app_stack_log_dir is defined',
            'app_stack_log_level is defined',
            'app_stack_python_version is defined',
            'app_stack_pip_packages is defined',
            'app_stack_log_max_size is defined',
            'app_stack_log_rotate_count is defined',
            'app_stack_secret_key is defined']"

# Confirm the secret fallback is not used
ansible "$TARGET_HOST" -m ansible.builtin.assert \
  -a "that=['app_stack_secret_key != \"changeme\"']"

# Confirm repository and revision availability
git ls-remote "$APP_REPOSITORY" "$APP_REVISION"

# Confirm the selected Python executable
python3 --version
```

- **Python application instance**
  - Verify the repository is reachable.
  - Verify the requested revision exists.
  - Verify the effective application directory, user, group, and port.
  - Verify the virtual environment and requirements installation.
  - Verify database migrations complete successfully.
  - Verify the application endpoint on the effective `app_stack_app_port`.
  - Verify the systemd service named by `app_stack_app_name` is enabled and running.

- **Database instance**
  - Verify `app_stack_db_host`, `app_stack_db_port`, `app_stack_db_name`, and `app_stack_db_user`.
  - Install and configure PostgreSQL only when `app_stack_db_host == 'localhost'`.
  - Do not install local PostgreSQL for the confirmed remote production host unless Hiera verification changes that conclusion.
  - Verify connectivity using the effective host, port, database, and user.
  - Verify the database user, database, and privileges.
  - Verify `/usr/local/bin/db-backup.sh`.
  - Verify the `database_backup` cron schedule and command.

- **Monitoring instance**
  - Verify `app_stack_monitoring_enabled` is intentionally true or false.
  - Do not assume virtual Puppet resources were realized.
  - When enabled, verify `prometheus-node-exporter`, `prometheus-pushgateway`, and `push_app_metrics`.
  - Verify `/usr/local/bin/app-healthcheck.sh`.
  - Verify the `app_health_check` cron schedule, command, user, and environment.

- **Systemd unit**
  - Reload systemd after deployment.
  - Validate the unit:

```yaml
- name: Validate application systemd unit
  ansible.builtin.command:
    cmd: systemd-analyze verify /etc/systemd/system/{{ app_stack_app_name }}.service
  changed_when: false
```

- **Log rotation**
  - Validate the configuration:

```yaml
- name: Validate logrotate configuration
  ansible.builtin.command:
    cmd: logrotate -d /etc/logrotate.d/{{ app_stack_app_name }}
  changed_when: false
```

- Validate the rendered `.env` file without printing its contents.
- Confirm Vault or external-secret access for:
  - common database password
  - production application secret
  - staging application secret
- Confirm the application service starts after daemon reload.
- Confirm database migrations run after the application code, virtual environment, requirements, and `.env` are deployed.