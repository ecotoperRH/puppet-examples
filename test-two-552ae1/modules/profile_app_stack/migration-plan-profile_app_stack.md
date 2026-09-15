---
source-path: site/modules/linux/profile_app_stack
---

# Migration Plan: profile_app_stack

**TLDR**: This module deploys a Python WSGI/ASGI web application stack on Linux. It installs Python 3 and creates a virtualenv, provisions a local or remote PostgreSQL database, clones the application from Git, writes a `.env` environment file, installs a systemd service unit running gunicorn, configures logrotate, deploys a health-check script, schedules a database backup cron job, and conditionally installs Prometheus monitoring tooling in production. The full role chain is `role::app_stack → profile::base::base → profile::app::stack → profile_app_stack`. Two environments are supported: **production** (remote DB, 8 workers, encrypted secrets) and **staging** (local DB, 1 worker, plaintext secret — security risk).

---

## Service Type and Instances

**Service Type**: Python WSGI/ASGI Application Server (gunicorn + uvicorn workers) with PostgreSQL database backend

**Configured Instances**:
- **myapp-api** (common default / staging): Python application server
  - Location/Path: `/opt/myapp-api`
  - Port/Socket: `0.0.0.0:8000`
  - Git Repo: `https://github.com/example-org/myapp-api.git`, revision `main`
  - Workers: 1 (staging), 2 (common default)
  - Log Dir: `/var/log/myapp-api`
  - DB: `localhost:5432/myapp_db` (staging/default)
- **myapp-api** (production override): Same application, production-tuned
  - Port/Socket: `0.0.0.0:8000`
  - Git Repo: same, revision `v2.4.1`
  - Workers: 8
  - DB: `db-primary.prod.internal:5432/myapp_db`
  - Log Level: `warning`

---

## File Structure

```
site/
├── role/
│   └── manifests/
│       └── app_stack.pp
├── profile/
│   └── manifests/
│       ├── app/
│       │   └── stack.pp
│       └── base/
│           └── base.pp
└── modules/
    ├── linux/
    │   └── profile_app_stack/
    │       ├── manifests/
    │       │   ├── init.pp
    │       │   ├── python.pp
    │       │   ├── database.pp
    │       │   ├── app.pp
    │       │   ├── service.pp
    │       │   └── monitoring.pp
    │       ├── templates/
    │       │   ├── logrotate.conf.erb
    │       │   ├── app.env.erb
    │       │   └── app.service.epp
    │       ├── files/
    │       │   ├── backup.sh
    │       │   └── healthcheck.sh
    │       ├── lib/
    │       │   └── puppet/
    │       │       └── functions/
    │       │           └── app_db_url.rb
    │       └── data/
    │           ├── common.yaml
    │           └── environment/
    │               ├── production.yaml
    │               └── staging.yaml
    └── common/
        └── base_utils/
            ├── manifests/
            │   └── init.pp
            └── data/
                ├── common.yaml
                └── os/
                    ├── Debian.yaml
                    └── RedHat.yaml
```

**Static file sources** (served from `puppet:///modules/profile_app_stack/`):
- `files/backup.sh` → deployed to `/usr/local/bin/db-backup.sh`
- `files/healthcheck.sh` → deployed to `/usr/local/bin/app-healthcheck.sh`

---

## Module Explanation

The module performs operations in this order:

### 1. **role::app_stack** (`site/role/manifests/app_stack.pp`)
- **Conditional** `if $facts['kernel'].downcase == 'linux'` (always true on target nodes):
  - `Exec[default]` → sets global `path` attribute: `/usr/bin:/bin:/usr/sbin:/sbin` for all `exec` resources in the catalog
- `include ::profile::base::base` (no containment — runs independently)
- `contain ::profile::app::stack`
- **Ordering**: `Class['::profile::base::base'] -> Class['::profile::app::stack']`

### 2. **profile::base::base** (`site/profile/manifests/base/base.pp`)
- Parameters: `manage_ntp=true`, `manage_syslog=true`, `manage_utils=true` (all Hiera defaults)
- **Conditional** `if $manage_utils` (true):
  - `include base_utils` → walks into **base_utils** below
- **Conditional** `if $manage_ntp and $facts['kernel'] == 'Linux'` (true):
  - `package 'chrony'` → ensure: `installed`
  - `service 'chronyd'` → ensure: `running`, enable: `true`
- **Conditional** `if $manage_syslog and $facts['kernel'] == 'Linux'` (true):
  - `package 'rsyslog'` → ensure: `installed`
  - `service 'rsyslog'` → ensure: `running`, enable: `true`

#### 2a. **base_utils** (`site/modules/common/base_utils/manifests/init.pp`)
- Parameters: `manage_motd=true`, `motd_template='base_utils/motd.erb'`, `utility_packages=[]` (common default, overridden by OS family)
- **Conditional** `if $manage_motd` (true):
  - `file '/etc/motd'` → content: rendered from template `base_utils/motd.erb`, owner: `root`, group: `root`, mode: `0644`
- **Loop** `$utility_packages.each` — runs **0 times** at common level; OS-family override provides actual list:
  - **Debian/Ubuntu** — loop runs **5 times** for: `vim`, `wget`, `curl`, `jq`, `dnsutils`
    - `package 'vim'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'dnsutils'` → ensure: `installed`
  - **RedHat/CentOS** — loop runs **5 times** for: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`
    - `package 'vim-enhanced'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'bind-utils'` → ensure: `installed`

### 3. **profile::app::stack** (`site/profile/manifests/app/stack.pp`)
- Reads `fact('environment')` → `'production'` or `'staging'`
- `class { 'profile_app_stack': }` → thin wrapper, delegates entirely to the module below

### 4. **profile_app_stack** (`site/modules/linux/profile_app_stack/manifests/init.pp`)
- Resolves all parameters from Hiera (see Variables section for full resolved values per environment)
- Computes `$db_url` via custom function `profile_app_stack::app_db_url(db_user, db_password, db_host, db_port, db_name)`:
  - **common/staging**: `postgresql://myapp_app:<encoded-password>@localhost:5432/myapp_db`
  - **production**: `postgresql://myapp_app:<encoded-password>@db-primary.prod.internal:5432/myapp_db`
- `contain profile_app_stack::python`
- `contain profile_app_stack::database`
- `contain profile_app_stack::app`
- `contain profile_app_stack::service`
- `contain profile_app_stack::monitoring`
- **Ordering chain**: `profile_app_stack::python -> profile_app_stack::database -> profile_app_stack::app ~> profile_app_stack::service -> profile_app_stack::monitoring`
  - (`~>` means app changes notify/restart service)

### 5. **profile_app_stack::python** (`site/modules/linux/profile_app_stack/manifests/python.pp`)
- Resolves: `python_version='python3'`, `pip_packages=['uvicorn', 'gunicorn', 'psycopg2-binary']`
- Builds `$python_packages` array: `['python3', 'python3-pip', 'python3-venv', 'python3-dev', 'git', 'build-essential']`
- `package 'python3'` → ensure: `installed`
- `package 'python3-pip'` → ensure: `installed`
- `package 'python3-venv'` → ensure: `installed`
- `package 'python3-dev'` → ensure: `installed`
- `package 'git'` → ensure: `installed`
- `package 'build-essential'` → ensure: `installed`
- `group 'myapp'` → ensure: `present`, system: `true`
- `user 'myapp'` → ensure: `present`, gid: `myapp`, home: `/opt/myapp-api`, shell: `/bin/bash`, system: `true`, managehome: `false`, require: `Group['myapp']`
- `file '/opt/myapp-api'` → ensure: `directory`, owner: `myapp`, group: `myapp`, mode: `0755`
- `exec 'create_app_venv'` → command: `python3 -m venv /opt/myapp-api/venv`, creates: `/opt/myapp-api/venv/bin/activate`, user: `myapp`, path: `['/usr/bin', '/usr/local/bin', '/bin']`, require: `[Package[$python_packages], File['/opt/myapp-api']]`
- `file '/var/log/myapp-api'` → ensure: `directory`, owner: `myapp`, group: `myapp`, mode: `0755`
- `file '/etc/logrotate.d/myapp-api'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: rendered from template `logrotate.conf.erb`
  - **Template** `logrotate.conf.erb` → `/etc/logrotate.d/myapp-api` (rendered once):
    - `@log_dir` = `/var/log/myapp-api`
    - `@log_rotate_count` = `7`
    - `@log_max_size` = `100M`
    - `@app_name` = `myapp-api`
    - Rendered output: daily rotation, 7 copies, compress+delaycompress, maxsize 100M, `postrotate: systemctl reload myapp-api`

### 6. **profile_app_stack::database** (`site/modules/linux/profile_app_stack/manifests/database.pp`)
- **Conditional** `if $profile_app_stack::db_host == 'localhost'`:
  - **True** in staging/common (db_host=`localhost`):
    - `package 'postgresql'` → ensure: `installed`
    - `package 'postgresql-contrib'` → ensure: `installed`
    - `service 'postgresql'` → ensure: `running`, enable: `true`, require: `Package['postgresql']`
    - `exec 'create_db_user'` → command: `sudo -u postgres psql -c "CREATE USER myapp_app WITH PASSWORD '<db_password>';"`, unless: `sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='myapp_app'" | grep -q 1`, path: `['/usr/bin', '/bin']`, require: `Service['postgresql']`
    - `exec 'create_database'` → command: `sudo -u postgres psql -c "CREATE DATABASE myapp_db OWNER myapp_app;"`, unless: `sudo -u postgres psql -tAc "SELECT 1 FROM pg_catalog.pg_database WHERE datname='myapp_db'" | grep -q 1`, path: `['/usr/bin', '/bin']`, require: `Exec['create_db_user']`
    - `exec 'grant_db_privileges'` → command: `sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE myapp_db TO myapp_app;"`, unless: `sudo -u postgres psql -tAc "SELECT has_database_privilege('myapp_app', 'myapp_db', 'CREATE')" | grep -q t`, path: `['/usr/bin', '/bin']`, require: `Exec['create_database']`
  - **False** in production (db_host=`db-primary.prod.internal`): PostgreSQL install/setup block is **skipped entirely**
- `file '/usr/local/bin/db-backup.sh'` → ensure: `file`, source: `puppet:///modules/profile_app_stack/backup.sh`, owner: `root`, group: `myapp`, mode: `0750` *(deployed in ALL environments)*
- `cron 'database_backup'` → command: `/usr/local/bin/db-backup.sh myapp_db localhost` (staging) or `/usr/local/bin/db-backup.sh myapp_db db-primary.prod.internal` (production), user: `root`, hour: `2`, minute: `30` *(scheduled in ALL environments)*

### 7. **profile_app_stack::app** (`site/modules/linux/profile_app_stack/manifests/app.pp`)
- `vcsrepo '/opt/myapp-api'` → ensure: `latest`, provider: `git`, source: `https://github.com/example-org/myapp-api.git`, revision: `main` (staging) / `v2.4.1` (production), user: `myapp`, require: `User['myapp']`
- `exec 'install_requirements'` → command: `/opt/myapp-api/venv/bin/pip install -r /opt/myapp-api/requirements.txt`, cwd: `/opt/myapp-api`, user: `myapp`, unless: `/opt/myapp-api/venv/bin/pip freeze | diff - /opt/myapp-api/requirements.txt > /dev/null 2>&1`, require: `[Vcsrepo['/opt/myapp-api'], Exec['create_app_venv']]`, **notifies**: `Class['profile_app_stack::service']`
- **Conditional** `if !empty($pip_packages)` — `pip_packages=['uvicorn', 'gunicorn', 'psycopg2-binary']` → **true**, loop runs **3 times**:
  - **uvicorn**:
    - `exec 'install_pip_uvicorn'` → command: `/opt/myapp-api/venv/bin/pip install uvicorn`, unless: `/opt/myapp-api/venv/bin/pip show uvicorn`, user: `myapp`, require: `Exec['create_app_venv']`
  - **gunicorn**:
    - `exec 'install_pip_gunicorn'` → command: `/opt/myapp-api/venv/bin/pip install gunicorn`, unless: `/opt/myapp-api/venv/bin/pip show gunicorn`, user: `myapp`, require: `Exec['create_app_venv']`
  - **psycopg2-binary**:
    - `exec 'install_pip_psycopg2-binary'` → command: `/opt/myapp-api/venv/bin/pip install psycopg2-binary`, unless: `/opt/myapp-api/venv/bin/pip show psycopg2-binary`, user: `myapp`, require: `Exec['create_app_venv']`
- `file '/opt/myapp-api/.env'` → ensure: `file`, owner: `myapp`, group: `myapp`, mode: `0600`, content: rendered from template `app.env.erb`, **notifies**: `Class['profile_app_stack::service']`
  - **Template** `app.env.erb` → `/opt/myapp-api/.env` (rendered once per run):
    - `@db_url` = `postgresql://myapp_app:<encoded-password>@<db_host>:5432/myapp_db`
    - `@app_name` = `myapp-api`
    - `@app_port` = `8000`
    - `@secret_key` = `<eyaml-decrypted>` (production) / `staging-not-secret-at-all` (staging)
    - `@log_level` = `warning` (production) / `debug` (staging) / `info` (common default)
    - `@log_dir` = `/var/log/myapp-api`
    - `@worker_count` = `8` (production) / `1` (staging) / `2` (common default)
    - `@facts['environment']` = `'production'` or `'staging'`
    - **Logic block 1** — `if @facts['environment'] == 'production'`:
      - **production**: renders `DEBUG=false`, `ALLOWED_HOSTS=*`, `CORS_ORIGINS=https://app.example.com,https://admin.example.com`
      - **staging/other**: renders `DEBUG=true`, `ALLOWED_HOSTS=*`, `CORS_ORIGINS=*`
- `file '/usr/local/bin/app-healthcheck.sh'` → ensure: `file`, source: `puppet:///modules/profile_app_stack/healthcheck.sh`, owner: `root`, group: `root`, mode: `0755`
- `exec 'run_db_migrations'` → command: `/opt/myapp-api/venv/bin/python -m alembic upgrade head`, cwd: `/opt/myapp-api`, user: `myapp`, environment: `["DATABASE_URL=postgresql://myapp_app:<encoded-password>@<db_host>:5432/myapp_db"]`, **refreshonly: true** (only runs when `Vcsrepo['/opt/myapp-api']` changes), subscribe: `Vcsrepo['/opt/myapp-api']`

### 8. **profile_app_stack::service** (`site/modules/linux/profile_app_stack/manifests/service.pp`)
- `file '/etc/systemd/system/myapp-api.service'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: rendered from EPP template `app.service.epp`, **notifies**: `Exec['systemd_daemon_reload']`
  - **Template** `app.service.epp` → `/etc/systemd/system/myapp-api.service` (rendered once):
    - `$app_name` = `myapp-api`
    - `$app_dir` = `/opt/myapp-api`
    - `$app_user` = `myapp`
    - `$app_group` = `myapp`
    - `$app_port` = `8000`
    - `$worker_count` = `8` (production) / `1` (staging) / `2` (common default)
    - `$worker_class` = `uvicorn.workers.UvicornWorker`
    - `$max_requests` = `5000` (production) / `100` (staging) / `1000` (common default)
    - `$graceful_timeout` = `30`
    - `$log_dir` = `/var/log/myapp-api`
    - `$log_level` = `warning` (production) / `debug` (staging) / `info` (common default)
    - **Logic block 1** — `TimeoutStopSec`: computed as `$graceful_timeout + 5` = `35`
    - **Logic block 2** — `ExecStart` gunicorn bind: `0.0.0.0:8000`
    - **Logic block 3** — `ReadWritePaths`: `/opt/myapp-api /var/log/myapp-api`
    - Rendered systemd unit: Type=notify, After=network.target postgresql.service, Restart=on-failure, RestartSec=5, NoNewPrivileges=true, ProtectSystem=strict, ProtectHome=true, PrivateTmp=true
- `exec 'systemd_daemon_reload'` → command: `systemctl daemon-reload`, path: `['/usr/bin', '/bin']`, **refreshonly: true** (only runs when notified by the service file above)
- `service 'myapp-api'` → ensure: `running`, enable: `true`, require: `[File['/etc/systemd/system/myapp-api.service'], Exec['systemd_daemon_reload']]`, subscribe: `File['/opt/myapp-api/.env']` (restarts when `.env` changes)
- **Ordering**: `File['/etc/systemd/system/myapp-api.service'] ~> Exec['systemd_daemon_reload']`

### 9. **profile_app_stack::monitoring** (`site/modules/linux/profile_app_stack/manifests/monitoring.pp`)
- `@package 'prometheus-node-exporter'` → **virtual** (declared but not applied unless realized), ensure: `installed`
- `@service 'prometheus-node-exporter'` → **virtual**, ensure: `running`, enable: `true`, require: `Package['prometheus-node-exporter']`
- `@package 'prometheus-pushgateway'` → **virtual**, ensure: `installed`
- `@cron 'push_app_metrics'` → **virtual**, command: `/usr/local/bin/app-healthcheck.sh --push-metrics`, user: `myapp`, minute: `*/5`, require: `[Package['prometheus-pushgateway'], File['/usr/local/bin/app-healthcheck.sh']]`
- **Conditional** `if $facts['environment'] == 'production'` — **production only**:
  - `realize Package['prometheus-node-exporter']` → **materializes** → `package 'prometheus-node-exporter'` → ensure: `installed`
  - `realize Service['prometheus-node-exporter']` → **materializes** → `service 'prometheus-node-exporter'` → ensure: `running`, enable: `true`
  - `realize Package['prometheus-pushgateway']` → **materializes** → `package 'prometheus-pushgateway'` → ensure: `installed`
  - `realize Cron['push_app_metrics']` → **materializes** → `cron 'push_app_metrics'` → command: `/usr/local/bin/app-healthcheck.sh --push-metrics`, user: `myapp`, minute: `*/5`
  - In **staging**: all four virtual resources remain unrealized — nothing is installed or scheduled
- `cron 'app_health_check'` → command: `/usr/local/bin/app-healthcheck.sh http://localhost:8000/health`, user: `root`, minute: `*/2` *(always active in ALL environments)*

---

## Variables

**Variable Flow Summary**: 22 variables across 3 Hiera levels for `profile_app_stack`; 3 variables across 3 Hiera levels for `base_utils`. Total: 25 variables, 6 Hiera files.

### Variable Definitions

**`site/modules/linux/profile_app_stack/data/common.yaml` (module defaults — lowest priority)** → Migration note: Base defaults for all nodes; maps to `defaults/main.yml` in Ansible role
- `profile_app_stack::app_name`: `myapp-api` (type: string)
- `profile_app_stack::app_repo`: `https://github.com/example-org/myapp-api.git` (type: string)
- `profile_app_stack::app_revision`: `main` (type: string) — **overridden in both environments**
- `profile_app_stack::app_port`: `8000` (type: integer)
- `profile_app_stack::app_dir`: `/opt/myapp-api` (type: string)
- `profile_app_stack::app_user`: `myapp` (type: string)
- `profile_app_stack::app_group`: `myapp` (type: string)
- `profile_app_stack::db_host`: `localhost` (type: string) — **overridden in production**
- `profile_app_stack::db_port`: `5432` (type: integer)
- `profile_app_stack::db_name`: `myapp_db` (type: string)
- `profile_app_stack::db_user`: `myapp_app` (type: string)
- `profile_app_stack::db_password`: `ENC[PKCS7,...]` (type: string, eyaml-encrypted) — **must become `vault_app_stack_db_password`**
- `profile_app_stack::worker_count`: `2` (type: integer) — **overridden in both environments**
- `profile_app_stack::worker_class`: `uvicorn.workers.UvicornWorker` (type: string)
- `profile_app_stack::max_requests`: `1000` (type: integer) — **overridden in both environments**
- `profile_app_stack::graceful_timeout`: `30` (type: integer)
- `profile_app_stack::log_dir`: `/var/log/myapp-api` (type: string)
- `profile_app_stack::log_level`: `info` (type: string) — **overridden in both environments**
- `profile_app_stack::log_max_size`: `100M` (type: string) — used in logrotate template only
- `profile_app_stack::log_rotate_count`: `7` (type: integer) — used in logrotate template only
- `profile_app_stack::python_version`: `python3` (type: string) — used in `manifests/python.pp` only
- `profile_app_stack::pip_packages`: `['uvicorn', 'gunicorn', 'psycopg2-binary']` (type: array) — used in `manifests/python.pp` and `manifests/app.pp`
- `profile_app_stack::secret_key`: **no common default** — falls back to hardcoded `'changeme'` if not set; environment-scoped only

**`site/modules/linux/profile_app_stack/data/environment/production.yaml` (production overrides)** → Migration note: Production-specific variables; maps to `group_vars/production.yml` in Ansible
- `profile_app_stack::app_revision`: `v2.4.1` (type: string) — overrides common `main`
- `profile_app_stack::worker_count`: `8` (type: integer) — overrides common `2`
- `profile_app_stack::max_requests`: `5000` (type: integer) — overrides common `1000`
- `profile_app_stack::log_level`: `warning` (type: string) — overrides common `info`
- `profile_app_stack::db_host`: `db-primary.prod.internal` (type: string) — overrides common `localhost`
- `profile_app_stack::db_port`: `5432` (type: integer) — redundant re-declaration, same value as common
- `profile_app_stack::secret_key`: `ENC[PKCS7,...]` (type: string, eyaml-encrypted) — **must become `vault_app_stack_secret_key_production`**

**`site/modules/linux/profile_app_stack/data/environment/staging.yaml` (staging overrides)** → Migration note: Staging-specific variables; maps to `group_vars/staging.yml` in Ansible
- `profile_app_stack::app_revision`: `main` (type: string) — redundant re-declaration of common value
- `profile_app_stack::worker_count`: `1` (type: integer) — overrides common `2`
- `profile_app_stack::max_requests`: `100` (type: integer) — overrides common `1000`
- `profile_app_stack::log_level`: `debug` (type: string) — overrides common `info`
- `profile_app_stack::db_host`: `localhost` (type: string) — redundant re-declaration of common value
- `profile_app_stack::secret_key`: `staging-not-secret-at-all` (type: string, **PLAINTEXT — security risk**) — **strongly recommend wrapping with ansible-vault**

**`site/modules/common/base_utils/data/common.yaml`** → Migration note: Base defaults for base_utils; maps to `defaults/main.yml` in base_utils role
- `base_utils::manage_motd`: `true` (type: boolean)
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string)
- `base_utils::utility_packages`: `[]` (type: array) — **overridden by OS-family files**

**`site/modules/common/base_utils/data/os/Debian.yaml`** → Migration note: OS-specific variables, loaded conditionally based on OS family; maps to `group_vars/Debian.yml`
- `base_utils::utility_packages`: `['vim', 'wget', 'curl', 'jq', 'dnsutils']` (type: array)

**`site/modules/common/base_utils/data/os/RedHat.yaml`** → Migration note: OS-specific variables, loaded conditionally based on OS family; maps to `group_vars/RedHat.yml`
- `base_utils::utility_packages`: `['vim-enhanced', 'wget', 'curl', 'jq', 'bind-utils']` (type: array)

### Variable Migration Summary

- **Common defaults**: 22 variables from `common.yaml` → `defaults/main.yml` (base configuration for all nodes)
- **OS-specific variables**: 1 variable (`utility_packages`) that varies by operating system family → `group_vars/Debian.yml`, `group_vars/RedHat.yml`
- **Environment-specific variables (production)**: 7 variables → `group_vars/production.yml`
- **Environment-specific variables (staging)**: 6 variables → `group_vars/staging.yml`
- **Encrypted variables**: 2 variables requiring Ansible Vault (`db_password` from common, `secret_key` from production); 1 plaintext staging secret (`secret_key`) strongly recommended for vaulting

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **`app_revision`**: common=`main`, production=`v2.4.1`, staging=`main` (redundant); merge strategy: first
- **`worker_count`**: common=`2`, production=`8`, staging=`1`; merge strategy: first
- **`max_requests`**: common=`1000`, production=`5000`, staging=`100`; merge strategy: first
- **`log_level`**: common=`info`, production=`warning`, staging=`debug`; merge strategy: first
- **`db_host`**: common=`localhost`, production=`db-primary.prod.internal`, staging=`localhost` (redundant); merge strategy: first
- **`db_port`**: common=`5432`, production=`5432` (redundant re-declaration); merge strategy: first
- **`secret_key`**: no common default (falls back to hardcoded `'changeme'`), production=eyaml-encrypted, staging=plaintext; merge strategy: first
- **`utility_packages`**: common=`[]`, Debian=`[vim, wget, curl, jq, dnsutils]`, RedHat=`[vim-enhanced, wget, curl, jq, bind-utils]`; merge strategy: first

### Merge Strategy Notes

- Variables using `first` (default) — First value found wins, no merging; applies to all variables in this module

---

## Custom Types and Providers

### `profile_app_stack::app_db_url` (`site/modules/linux/profile_app_stack/lib/puppet/functions/app_db_url.rb`)
- **Purpose**: Assembles a PostgreSQL `DATABASE_URL` string in the format `postgresql://user:password@host:port/database`
- **Behavior**: Performs minimal percent-encoding on the password — only encodes `%`, `@`, `:`, `/`
- **Parameters**: `user` (String), `password` (String), `host` (String), `port` (Integer), `database` (String)
- **Ansible equivalent**: Jinja2 expression — `"postgresql://{{ app_db_user }}:{{ app_db_password | urlencode }}@{{ app_db_host }}:{{ app_db_port }}/{{ app_db_name }}"`
  - **Warning**: Ansible's built-in `urlencode` filter encodes more characters than this function. For strict parity, a custom Jinja2 filter plugin replicating only the four-character substitution (`%→%25`, `@→%40`, `:→%3A`, `/→%2F`) is required.

---

## Dependencies

**External module dependencies**:
- `puppetlabs-vcsrepo` (6.1.0) — provides `vcsrepo` resource type for Git clone/update in `manifests/app.pp`
- `puppetlabs-stdlib` (9.7.0) — provides `lookup()`, `empty()`, and other utility functions
- `puppetlabs-concat` (9.0.2) — declared as a dependency but not directly used in the execution tree
- `puppetlabs-firewall` (8.1.3) — declared as a dependency but not directly used in the execution tree
- `puppet-redis` (11.0.0) — declared as a dependency but not directly used in the execution tree
- `puppetlabs-apt` (9.4.0) — declared as a dependency but not directly used in the execution tree

**System package dependencies** (installed by the module):
- `python3`, `python3-pip`, `python3-venv`, `python3-dev`, `git`, `build-essential` (all environments)
- `postgresql`, `postgresql-contrib` (staging/localhost only)
- `prometheus-node-exporter`, `prometheus-pushgateway` (production only)
- `chrony`, `rsyslog` (via `profile::base::base`, all environments)
- OS-family utility packages (via `base_utils`): `vim`, `wget`, `curl`, `jq`, `dnsutils` (Debian) or `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils` (RedHat)

**Service dependencies** (ordering requirements):
- `profile_app_stack::python` must complete before `profile_app_stack::database`
- `profile_app_stack::database` must complete before `profile_app_stack::app`
- `profile_app_stack::app` completion notifies (and may restart) `profile_app_stack::service`
- `profile_app_stack::service` must complete before `profile_app_stack::monitoring`
- `profile::base::base` must complete before `profile::app::stack`
- Within database: `postgresql` service → `create_db_user` → `create_database` → `grant_db_privileges`

---

## Puppet Facts Used

- `$facts['kernel']` — kernel name (e.g., `Linux`); used in `site/role/manifests/app_stack.pp` to set global exec path, and in `site/profile/manifests/base/base.pp` to gate NTP and syslog management
- `$facts['environment']` — Puppet environment name (`production` or `staging`); used in `site/modules/linux/profile_app_stack/manifests/monitoring.pp` to decide whether to realize virtual monitoring resources, and in `site/modules/linux/profile_app_stack/templates/app.env.erb` to set `DEBUG` and `CORS_ORIGINS`
- `fact('environment')` — same as above, accessed via stdlib `fact()` function in `site/profile/manifests/app/stack.pp`
- `$facts['os']['family']` — OS family (`Debian` or `RedHat`); used implicitly by Hiera hierarchy to select `utility_packages` list in `base_utils`

---

## Template Conversion Notes

### `site/modules/linux/profile_app_stack/templates/logrotate.conf.erb` → `/etc/logrotate.d/myapp-api`
- **Variables**: `@log_dir` (`/var/log/myapp-api`), `@log_rotate_count` (`7`), `@log_max_size` (`100M`), `@app_name` (`myapp-api`)
- **Logic**: None — pure variable substitution
- **Rendered once** per Puppet run
- **Ansible**: Straightforward Jinja2 template; all four variables map directly to Ansible vars

### `site/modules/linux/profile_app_stack/templates/app.env.erb` → `/opt/myapp-api/.env`
- **Variables**: `@db_url`, `@app_name`, `@app_port`, `@secret_key`, `@log_level`, `@log_dir`, `@worker_count`, `@facts['environment']`
- **Logic block 1** — environment conditional:
  - `if @facts['environment'] == 'production'` → `DEBUG=false`, `CORS_ORIGINS=https://app.example.com,https://admin.example.com`
  - `else` → `DEBUG=true`, `CORS_ORIGINS=*`
- **Rendered once** per Puppet run; file mode `0600` (sensitive — contains `SECRET_KEY` and `DATABASE_URL`)
- **Ansible**: Use `when: env == 'production'` in task or a Jinja2 `{% if %}` block; `db_url` must be assembled via Jinja2 expression (see Custom Types and Providers section for encoding caveat)

### `site/modules/linux/profile_app_stack/templates/app.service.epp` → `/etc/systemd/system/myapp-api.service`
- **Variables**: `$app_name`, `$app_dir`, `$app_user`, `$app_group`, `$app_port`, `$worker_count`, `$worker_class`, `$max_requests`, `$graceful_timeout`, `$log_dir`, `$log_level` (11 variables, all passed explicitly)
- **Logic block 1** — `TimeoutStopSec`: arithmetic expression `$graceful_timeout + 5` = `35`
- **Logic block 2** — gunicorn `ExecStart` multi-line with all tuning parameters; bind address: `0.0.0.0:8000`
- **Logic block 3** — `ReadWritePaths`: concatenates `$app_dir` and `$log_dir` → `/opt/myapp-api /var/log/myapp-api`
- **Rendered once** per Puppet run; changes trigger `systemctl daemon-reload` then service restart
- **Ansible**: EPP is structurally equivalent to Jinja2; arithmetic `graceful_timeout + 5` works natively in Jinja2; use `notify: [Reload systemd, Restart myapp-api service]` handler chain

---

## PuppetDB Dependencies

No PuppetDB `puppetdb_query()` calls detected and no exported resources (`@@`) present.

**Virtual resource pattern** (in `site/modules/linux/profile_app_stack/manifests/monitoring.pp`): The module uses Puppet's `@resource` / `realize()` pattern (not exported resources `@@`). This is a **local** virtual resource pattern — resources are declared but only applied when explicitly realized. This pattern has no PuppetDB dependency and maps cleanly to Ansible `when: env == 'production'` conditionals.

---

## Checks for the Migration

**Files to verify after migration**:
- `/opt/myapp-api/` — directory exists, owner `myapp:myapp`, mode `0755`
- `/opt/myapp-api/venv/bin/activate` — virtualenv created successfully
- `/opt/myapp-api/.env` — exists, mode `0600`, contains correct `DATABASE_URL` and `SECRET_KEY`
- `/opt/myapp-api/requirements.txt` — present after git clone
- `/var/log/myapp-api/` — directory exists, owner `myapp:myapp`, mode `0755`
- `/etc/logrotate.d/myapp-api` — exists, owner `root:root`, mode `0644`
- `/etc/systemd/system/myapp-api.service` — exists, owner `root:root`, mode `0644`
- `/usr/local/bin/db-backup.sh` — exists, owner `root:myapp`, mode `0750`
- `/usr/local/bin/app-healthcheck.sh` — exists, owner `root:root`, mode `0755`
- `/etc/motd` — exists, owner `root:root`, mode `0644`

**Service endpoints to check**:
- `http://localhost:8000/health` — application health endpoint (checked by `app_health_check` cron every 2 minutes)
- PostgreSQL port `5432` — local `localhost:5432` (staging) or remote `db-primary.prod.internal:5432` (production)
- Prometheus node exporter port `9100` — production only

**Templates rendered**:
- `site/modules/linux/profile_app_stack/templates/logrotate.conf.erb` → `/etc/logrotate.d/myapp-api` (1 render per run)
- `site/modules/linux/profile_app_stack/templates/app.env.erb` → `/opt/myapp-api/.env` (1 render per run; environment-conditional content)
- `site/modules/linux/profile_app_stack/templates/app.service.epp` → `/etc/systemd/system/myapp-api.service` (1 render per run; triggers daemon-reload on change)

## Pre-flight checks:
```bash
# --- Service status ---
systemctl status myapp-api
systemctl is-enabled myapp-api

# --- Staging/localhost PostgreSQL checks ---
systemctl status postgresql
sudo -u postgres psql -c "\du"                          # verify myapp_app user exists
sudo -u postgres psql -c "\l"                           # verify myapp_db database exists
sudo -u postgres psql -tAc "SELECT has_database_privilege('myapp_app', 'myapp_db', 'CREATE')"

# --- Production remote DB connectivity ---
psql "postgresql://myapp_app@db-primary.prod.internal:5432/myapp_db" -c "\conninfo"

# --- Virtualenv and pip packages ---
/opt/myapp-api/venv/bin/pip freeze | grep gunicorn
/opt/myapp-api/venv/bin/pip freeze | grep uvicorn
/opt/myapp-api/venv/bin/pip freeze | grep psycopg2-binary

# --- Application files ---
stat /opt/myapp-api/.env                                # verify mode 0600
stat /usr/local/bin/db-backup.sh                        # verify mode 0750, owner root:myapp
stat /usr/local/bin/app-healthcheck.sh                  # verify mode 0755
stat /etc/systemd/system/myapp-api.service              # verify mode 0644
stat /etc/logrotate.d/myapp-api                         # verify mode 0644

# --- Cron entries ---
crontab -l -u root                                      # verify database_backup (02:30) and app_health_check (*/2)
crontab -l -u myapp                                     # verify push_app_metrics (*/5) — production only

# --- Systemd and application health ---
systemctl daemon-reload
journalctl -u myapp-api --no-pager -n 50
curl -sf http://localhost:8000/health

# --- Prometheus monitoring (production only) ---
systemctl status prometheus-node-exporter
systemctl status prometheus-pushgateway
curl -sf http://localhost:9100/metrics | head -5

# --- Base services (all environments) ---
systemctl status chronyd
systemctl status rsyslog
```