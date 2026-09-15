---
source-path: modules/puppetdb_query_stub
---

# Migration Plan: puppetdb_query_stub (role::haproxy)

**TLDR**: This module configures a Linux HAProxy load balancer node. The `puppetdb_query_stub` is a supporting stub function — not a service in its own right — that returns an empty array in place of real PuppetDB queries. The actual service being deployed is HAProxy, composed from `role::haproxy` → `profile::base::base` + `profile::loadbalancer::haproxy` → `profile_haproxy` (install / config / discover / service / firewall). The stub's only effect at runtime is that the dynamic backend discovery loop in `profile_haproxy::discover` runs **zero times**, meaning all backends are statically defined via Hiera. The migration must replicate: HAProxy package + user/group, static config from Hiera-merged backends, error pages, logrotate, firewall rules (ufw on Debian, firewalld on RedHat), and base OS utilities (chrony, rsyslog, motd, utility packages).

---

## Service Type and Instances

**Service Type**: Load Balancer (HAProxy)

**Configured Instances**:
- **haproxy** (primary service):
  - Config file: `/etc/haproxy/haproxy.cfg`
  - Config dir: `/etc/haproxy/` with `/etc/haproxy/conf.d/` for per-backend fragments
  - Service name: `haproxy`
  - Stats endpoint: port `9001` on node `lb01.fra.example.com` (disabled in production environment default, overridden true at node level)
  - Stats URI: `/haproxy-stats`, user: `admin`, password: eyaml-encrypted
  - SSL termination: enabled in production (`ssl_enabled: true`), cert at `/etc/ssl/certs`, key at `/etc/ssl/private`

- **webservers backend** (deep-merged, effective for dc1_fra):
  - Balance: `roundrobin`, port: `8080`
  - Health check: `httpchk GET /health`, interval: `5s`
  - Servers: `web1-fra` (10.100.1.10 w=100), `web2-fra` (10.100.1.11 w=100), `web3-fra` (10.100.1.12 w=100)

- **api backend** (deep-merged, effective for lb01.fra.example.com):
  - Balance: `leastconn`, port: `3000`
  - Health check: `httpchk GET /api/health`, interval: `10s`
  - Servers: `api1-fra` (10.100.2.10 w=200 — node override), `api2-fra` (10.100.2.11 w=100)

- **internal_monitoring backend** (cluster-level addition, haproxy_prod_fra only):
  - Balance: `roundrobin`, port: `9090`
  - Health check: `httpchk GET /-/healthy`, interval: `15s`
  - Servers: `prom1-fra` (10.100.3.10 w=100)

---

## File Structure

```
site/role/manifests/haproxy.pp
site/profile/manifests/base/base.pp
site/profile/manifests/loadbalancer/haproxy.pp
site/modules/common/base_utils/manifests/init.pp
site/modules/linux/profile_haproxy/manifests/init.pp
site/modules/linux/profile_haproxy/manifests/install.pp
site/modules/linux/profile_haproxy/manifests/config.pp
site/modules/linux/profile_haproxy/manifests/discover.pp
site/modules/linux/profile_haproxy/manifests/service.pp
site/modules/linux/profile_haproxy/manifests/firewall.pp

modules/puppetdb_query_stub/lib/puppet/functions/puppetdb_query.rb

modules/profile_haproxy/data/common.yaml
modules/profile_haproxy/data/environment/production.yaml
modules/profile_haproxy/data/environment/staging.yaml
modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml
modules/profile_haproxy/data/datacenter/dc1_fra.yaml
modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml
site/modules/linux/profile_haproxy/data/os/Debian.yaml
site/modules/linux/profile_haproxy/data/os/RedHat.yaml
site/modules/common/base_utils/data/common.yaml
site/modules/common/base_utils/data/os/Debian.yaml
site/modules/common/base_utils/data/os/RedHat.yaml
```

---

## Module Explanation

The module performs operations in this order:

### 1. **role::haproxy** (`site/role/manifests/haproxy.pp`)
- **Conditional** `if $facts['kernel'].downcase == 'linux'` (always true on Linux targets):
  - `Exec[default]` → sets global `path` resource default: `/usr/bin:/bin:/usr/sbin:/sbin` (applies to all `exec` resources in the catalog)
- `include ::profile::base::base` (no containment — runs independently)
- `contain ::profile::loadbalancer::haproxy` (contained)
- **Ordering**: `Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']`

---

### 2. **profile::base::base** (`site/profile/manifests/base/base.pp`)
- Parameters are manifest-level defaults (no supporting Hiera data file was identified for this class; the values below are asserted from manifest defaults, not confirmed from a Hiera data file):
  - `manage_utils: true`, `manage_ntp: true`, `manage_syslog: true`
- **Conditional** `if $manage_utils` → `true`:
  - `include base_utils` → walks into **base_utils** (see §3)
- **Conditional** `if $manage_ntp and $facts['kernel'] == 'Linux'` → `true`:
  - `package 'chrony'` → ensure: `installed`
  - `service 'chronyd'` → ensure: `running`, enable: `true`
- **Conditional** `if $manage_syslog and $facts['kernel'] == 'Linux'` → `true`:
  - `package 'rsyslog'` → ensure: `installed`
  - `service 'rsyslog'` → ensure: `running`, enable: `true`

---

### 3. **base_utils** (`site/modules/common/base_utils/manifests/init.pp`)
- Parameters resolved from Hiera:
  - `manage_motd: true` (from `site/modules/common/base_utils/data/common.yaml`)
  - `motd_template: 'base_utils/motd.erb'`
  - `utility_packages: []` (common default) — overridden by OS-level data:
    - **Debian**: `[vim, wget, curl, jq, dnsutils]`
    - **RedHat**: `[vim-enhanced, wget, curl, jq, bind-utils]`
- **Conditional** `if $manage_motd` → `true`:
  - `file '/etc/motd'` → ensure: `file`, content: rendered from template `base_utils/motd.erb`, owner: `root`, group: `root`, mode: `0644`
- **Loop** `$utility_packages.each |$pkg|`:
  - **On Debian** — runs 5 times:
    - `package 'vim'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'dnsutils'` → ensure: `installed`
  - **On RedHat** — runs 5 times:
    - `package 'vim-enhanced'` → ensure: `installed`
    - `package 'wget'` → ensure: `installed`
    - `package 'curl'` → ensure: `installed`
    - `package 'jq'` → ensure: `installed`
    - `package 'bind-utils'` → ensure: `installed`

---

### 4. **profile::loadbalancer::haproxy** (`site/profile/manifests/loadbalancer/haproxy.pp`)
- Reads `fact('environment')` → `$environment_name` (used for context only, not passed to subclass)
- `class { 'profile_haproxy': }` → delegates entirely to **profile_haproxy** (see §5)

---

### 5. **profile_haproxy** (`site/modules/linux/profile_haproxy/manifests/init.pp`)
- All parameters resolved via Hiera (effective values shown for `lb01.fra.example.com` in production/dc1_fra/haproxy_prod_fra):
  - `package_name: 'haproxy'`
  - `config_dir: '/etc/haproxy'`
  - `config_file: '/etc/haproxy/haproxy.cfg'`
  - `service_name: 'haproxy'`
  - `user: 'haproxy'`
  - `group: 'haproxy'`
  - `stats_enabled: true` (node lb01.fra.example.com overrides production `false`)
  - `stats_port: 9001` (node override of common `9000`)
  - `stats_uri: '/haproxy-stats'`
  - `stats_user: 'admin'`
  - `stats_password: <eyaml-encrypted>` (wrapped in `Sensitive[]`)
  - `global_maxconn: 32768` (cluster haproxy_prod_fra overrides production value of 16384)
  - `client_timeout: '60s'` (production override of common `30s`)
  - `server_timeout: '60s'` (production override of common `30s`)
  - `connect_timeout: '5s'`
  - `retries: 3`
  - `ssl_enabled: true` (production override of common `false`)
  - `ssl_cert_path: '/etc/ssl/certs'`
  - `ssl_key_path: '/etc/ssl/private'`
  - `ssl_ciphers: 'ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384'` (cluster override of common AES128 suite)
  - `ssl_min_version: 'TLSv1.3'` (cluster override of common `TLSv1.2`)
  - `log_server: '10.100.1.50'` (datacenter dc1_fra override of common `127.0.0.1`)
  - `log_facility: 'local0'`
  - `log_level: 'warning'` (production override of common `info`)
  - `backends: <deep-merged hash>` (see §5a below)
- `contain profile_haproxy::install`
- `contain profile_haproxy::config`
- `contain profile_haproxy::discover`
- `contain profile_haproxy::service`
- `contain profile_haproxy::firewall`
- **Ordering**:
  - `Class['profile_haproxy::install'] -> Class['profile_haproxy::config']`
  - `Class['profile_haproxy::config'] -> Class['profile_haproxy::discover']`
  - `Class['profile_haproxy::discover'] ~> Class['profile_haproxy::service']` (notify/restart)
  - `Class['profile_haproxy::firewall']` runs in parallel (no explicit ordering to firewall class)

#### 5a. Effective `backends` hash (deep-merged result for lb01.fra.example.com in haproxy_prod_fra/dc1_fra/production)

```yaml
backends:
  webservers:                          # from common + dc1_fra server override
    balance: roundrobin
    port: 8080
    health_check: "httpchk GET /health"
    health_interval: 5s
    servers:
      - { name: web1-fra, address: 10.100.1.10, weight: 100 }
      - { name: web2-fra, address: 10.100.1.11, weight: 100 }
      - { name: web3-fra, address: 10.100.1.12, weight: 100 }
  api:                                 # from common + dc1_fra + lb01 node weight override
    balance: leastconn
    port: 3000
    health_check: "httpchk GET /api/health"
    health_interval: 10s
    servers:
      - { name: api1-fra, address: 10.100.2.10, weight: 200 }  # node override: weight 200
      - { name: api2-fra, address: 10.100.2.11, weight: 100 }
  internal_monitoring:                 # added by cluster/haproxy_prod_fra only
    balance: roundrobin
    port: 9090
    health_check: "httpchk GET /-/healthy"
    health_interval: 15s
    servers:
      - { name: prom1-fra, address: 10.100.3.10, weight: 100 }
```

---

### 6. **profile_haproxy::install** (`site/modules/linux/profile_haproxy/manifests/install.pp`)
- Looks up `profile_haproxy::extra_packages` (first-merge, default `[]`):
  - **Debian**: `['hatop']`
  - **RedHat**: `['haproxy-systemd-wrapper', 'policycoreutils-python-utils']`
- Looks up `profile_haproxy::selinux_enabled` (first-merge, default `false`):
  - **Debian**: `false`
  - **RedHat**: `true`
- `package 'haproxy'` → ensure: `installed`
- **Conditional** `if !empty($extra_packages)`:
  - **On Debian** — `package 'hatop'` → ensure: `installed`, require: `Package['haproxy']`
  - **On RedHat** — `package 'haproxy-systemd-wrapper'` → ensure: `installed`, require: `Package['haproxy']`
  - **On RedHat** — `package 'policycoreutils-python-utils'` → ensure: `installed`, require: `Package['haproxy']`
- `group 'haproxy'` → ensure: `present`, system: `true`
- `user 'haproxy'` → ensure: `present`, gid: `haproxy`, home: `/var/lib/haproxy`, shell: `/sbin/nologin`, system: `true`, require: `Group['haproxy']`
- `file ['/etc/haproxy', '/etc/haproxy/conf.d']` → ensure: `directory`, owner: `root`, group: `haproxy`, mode: `0755`
- `file '/var/lib/haproxy'` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0750`
- **Conditional** `if $selinux_enabled`:
  - **On Debian**: skipped (`selinux_enabled: false`)
  - **On RedHat**: `exec 'haproxy_selinux_connect'` → command: `setsebool -P haproxy_connect_any 1`, unless: `getsebool haproxy_connect_any | grep -q on`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, require: `Package['haproxy']`

---

### 7. **profile_haproxy::config** (`site/modules/linux/profile_haproxy/manifests/config.pp`)
- `file '/etc/haproxy/haproxy.cfg'` (template `profile_haproxy/haproxy.cfg.erb`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`
  - Template variables passed: `global_maxconn=32768`, `client_timeout=60s`, `server_timeout=60s`, `connect_timeout=5s`, `retries=3`, `log_server=10.100.1.50`, `log_facility=local0`, `log_level=warning`, `ssl_enabled=true`, `ssl_cert_path=/etc/ssl/certs`, `ssl_key_path=/etc/ssl/private`, `ssl_ciphers=ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`, `ssl_min_version=TLSv1.3`, `stats_enabled=true`, `stats_port=9001`, `stats_uri=/haproxy-stats`, `stats_user=admin`, `stats_password=<sensitive>`
  - **notifies**: `Class['profile_haproxy::service']`

- **Loop** `$profile_haproxy::backends.each |$backend_name, $backend_config|` — runs **3 times** (webservers, api, internal_monitoring):

  - **webservers**:
    - `file '/etc/haproxy/conf.d/webservers.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`
      - Template variables: `backend_name=webservers`, `balance=roundrobin`, `port=8080`, `servers=[{web1-fra,10.100.1.10,100},{web2-fra,10.100.1.11,100},{web3-fra,10.100.1.12,100}]`, `health_check=httpchk GET /health`, `health_interval=5s`, `ssl_enabled=true`
      - **notifies**: `Class['profile_haproxy::service']`

  - **api**:
    - `file '/etc/haproxy/conf.d/api.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`
      - Template variables: `backend_name=api`, `balance=leastconn`, `port=3000`, `servers=[{api1-fra,10.100.2.10,200},{api2-fra,10.100.2.11,100}]`, `health_check=httpchk GET /api/health`, `health_interval=10s`, `ssl_enabled=true`
      - **notifies**: `Class['profile_haproxy::service']`

  - **internal_monitoring**:
    - `file '/etc/haproxy/conf.d/internal_monitoring.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`
      - Template variables: `backend_name=internal_monitoring`, `balance=roundrobin`, `port=9090`, `servers=[{prom1-fra,10.100.3.10,100}]`, `health_check=httpchk GET /-/healthy`, `health_interval=15s`, `ssl_enabled=true`
      - **notifies**: `Class['profile_haproxy::service']`

- **Loop** `['503', '408'].each |$code|` — runs **2 times**:
  - `file '/etc/haproxy/errors/503.http'` → ensure: `file`, source: `puppet:///modules/profile_haproxy/haproxy_errors/503.http`, owner: `root`, group: `haproxy`, mode: `0644`
  - `file '/etc/haproxy/errors/408.http'` → ensure: `file`, source: `puppet:///modules/profile_haproxy/haproxy_errors/408.http`, owner: `root`, group: `haproxy`, mode: `0644`

- `file '/etc/haproxy/errors'` → ensure: `directory`, owner: `root`, group: `haproxy`, mode: `0755`, before: `File['/etc/haproxy/errors/503.http']`

- Looks up `profile_haproxy::stick_table_enabled` (first-merge, default `false`):
  - **production**: `true` (from `environment/production.yaml`)
  - **staging**: `false`
- **Conditional** `if $stick_table_enabled` (production = `true`):
  - Looks up `profile_haproxy::stick_table_size: '200k'`
  - Looks up `profile_haproxy::stick_table_expire: '30m'`
  - `file '/etc/haproxy/conf.d/stick-tables.cfg'` → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, content: `"# Managed by Puppet\nstick-table type ip size 200k expire 30m\n"`
    - **notifies**: `Class['profile_haproxy::service']`

---

### 8. **profile_haproxy::discover** (`site/modules/linux/profile_haproxy/manifests/discover.pp`)

> **Note on two distinct backend-population patterns in this class**: The `webservers` backend is populated via an export/collect pattern (PuppetDB exported resources). The `api` backend is populated via a direct PuppetDB query loop (`$app_servers.each`). These are separate mechanisms. With the stub active, both result in zero dynamic resources — but they must be migrated differently in Ansible (see PuppetDB Dependencies section).

- **Exported resource** `@@haproxy::balancermember[$facts['networking']['fqdn']]`:
  - `listening_service: 'webservers'`, `server_names: <node FQDN>`, `ipaddresses: <node IP>`, `ports: '8080'`, `options: 'check'`
  - This exports the current node's membership into PuppetDB for other nodes to collect. **In Ansible: no equivalent — static inventory replaces this pattern.**

- **Collector** `Haproxy::Balancermember <<| listening_service == 'webservers' |>>`:
  - Realizes all exported `haproxy::balancermember` resources tagged `listening_service == 'webservers'` from PuppetDB. With the stub active, this collector realizes zero resources.
  - **In Ansible**: Static `haproxy_backends.webservers.servers` list in `group_vars` or dynamic inventory group iteration.

- **PuppetDB query** `puppetdb_query("resources[certname, parameters] { type = 'Class' and title = 'Profile::App_server' and certname in resources[certname] { type = 'Class' and title = 'Profile::Base' and parameters.environment = '${facts['puppet_environment']}' } }")`:
  - **STUB ACTIVE**: `puppetdb_query_stub` intercepts this call, logs a warning, and returns `[]` (empty array)
  - `$app_servers = []`

- **Loop** `$app_servers.each |$server|` — **runs 0 times** (stub returns empty array):
  - *Instance expansion (what would run if PuppetDB were live)*: For each app server node classified with `Profile::App_server` in the same Puppet environment, a `haproxy::balancermember "api-${certname}"` resource would be created with `listening_service: 'api'`, `server_names: <certname>`, `ipaddresses: <certname>`, `ports: <app_port from parameters>`, `options: 'check inter 10s'`
  - These are **direct resources** (not exported/collected) — distinct from the `webservers` export/collect pattern above.
  - **In Ansible**: Replace with static inventory group `app_servers` or a dynamic inventory plugin; iterate over `groups['app_servers']` to build the api backend server list.

---

### 9. **profile_haproxy::service** (`site/modules/linux/profile_haproxy/manifests/service.pp`)
- `service 'haproxy'` → ensure: `running`, enable: `true`, hasrestart: `true`, hasstatus: `true`, require: `Package['haproxy']`, subscribe: `File['/etc/haproxy/haproxy.cfg']`
- `exec 'haproxy_config_check'` → command: `haproxy -c -f /etc/haproxy/haproxy.cfg`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, refreshonly: `true`, subscribe: `File['/etc/haproxy/haproxy.cfg']`, before: `Service['haproxy']`
- `file '/etc/logrotate.d/haproxy'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: heredoc logrotate config (daily, rotate 14, compress, delaycompress, postrotate: `kill -HUP $(cat /var/run/haproxy.pid)`)
- **Notification chain**:
  - `File['/etc/haproxy/haproxy.cfg'] ~> Exec['haproxy_config_check']`
  - `Exec['haproxy_config_check'] -> Service['haproxy']`
  - `File['/etc/haproxy/haproxy.cfg'] ~> Service['haproxy']`

---

### 10. **profile_haproxy::firewall** (`site/modules/linux/profile_haproxy/manifests/firewall.pp`)
- Looks up `profile_haproxy::firewall_provider` (first-merge):
  - **Debian**: `'ufw'`
  - **RedHat**: `'firewalld'`
- Calls `base_utils::normalize_port($profile_haproxy::stats_port)` → normalizes `9001` to Integer `9001`
  - Note: `normalize_port` is a function defined in the `base_utils` module, not from `puppetlabs-stdlib`.
- **Case** `$firewall_provider`:

  - **Branch `firewalld`** (RedHat):
    - Looks up `profile_haproxy::firewall_zone` (default `'public'`) → `'public'`
    - **Loop** `['80', '443'].each |$port|` — runs 2 times:
      - `exec 'firewalld_allow_80'` → command: `firewall-cmd --zone=public --add-port=80/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=80/tcp`, path: `['/usr/bin', '/bin']`, notify: `Exec['firewalld_reload']`
      - `exec 'firewalld_allow_443'` → command: `firewall-cmd --zone=public --add-port=443/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=443/tcp`, path: `['/usr/bin', '/bin']`, notify: `Exec['firewalld_reload']`
    - **Conditional** `if $profile_haproxy::stats_enabled` → `true` (on lb01.fra.example.com):
      - `exec 'firewalld_allow_stats_9001'` → command: `firewall-cmd --zone=public --add-port=9001/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=9001/tcp`, path: `['/usr/bin', '/bin']`, notify: `Exec['firewalld_reload']`
    - `exec 'firewalld_reload'` → command: `firewall-cmd --reload`, path: `['/usr/bin', '/bin']`, refreshonly: `true`
    - **Migration note**: The exec resources `firewalld_allow_80`, `firewalld_allow_443`, `firewalld_allow_stats_9001` are inferred from the branch description in the structured analysis; the analysis tree only explicitly lists `exec[firewalld_reload]`. Confirm presence in source manifests before migration.

  - **Branch `ufw`** (Debian):
    - `package 'ufw'` → ensure: `installed`
    - `exec 'ufw_allow_http'` → command: `ufw allow 80/tcp`, unless: `ufw status | grep -q "80/tcp.*ALLOW"`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, require: `Package['ufw']`
    - `exec 'ufw_allow_https'` → command: `ufw allow 443/tcp`, unless: `ufw status | grep -q "443/tcp.*ALLOW"`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, require: `Package['ufw']`
    - **Conditional** `if $profile_haproxy::stats_enabled` → `true` (on lb01.fra.example.com):
      - `exec 'ufw_allow_stats'` → command: `ufw allow 9001/tcp`, unless: `ufw status | grep -q '9001/tcp.*ALLOW'`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, require: `Package['ufw']`
    - `exec 'ufw_enable'` → command: `ufw --force enable`, unless: `ufw status | grep -q "Status: active"`, path: `['/usr/sbin', '/usr/bin', '/sbin', '/bin']`, require: `Package['ufw']`
    - **Migration note**: `ufw_allow_stats` is inferred from the branch description; confirm presence in source manifests before migration.

  - **Branch `default`**: `notify 'Unknown firewall provider: <value>'` (warning only, no resources)

---

## Variables

**Variable Flow Summary**: 40+ variables across 8 Hiera levels (common, environment/production, environment/staging, cluster/haproxy_prod_fra, datacenter/dc1_fra, nodes/lb01.fra.example.com, os/Debian, os/RedHat)

> **Note on Hiera level numbering**: The level numbers below (L1, L3, L9, etc.) reflect priority within the `profile_haproxy` module's Hiera hierarchy only — lower number = higher priority. The `base_utils` module uses a separate, shorter hierarchy with its own numbering. These numbers are module-internal and not globally comparable across modules.

> **Note on datacenter hierarchy placement**: `datacenter/dc1_fra.yaml` is assigned L11 (lower priority than environment L9). This means if an environment file also defined `log_server`, the environment value would win. No environment file defines `log_server` in this plan, so there is no current conflict — but this is an unusual hierarchy design. **Migration risk**: If the actual Hiera hierarchy places datacenter *above* environment, the level assignments here are incorrect. Verify the `hiera.yaml` hierarchy ordering before migration.

### Variable Definitions

**`modules/profile_haproxy/data/common.yaml` (L21 — lowest priority)** → Migration note: Base defaults for all nodes; map to `defaults/main.yml` in Ansible role
- `profile_haproxy::package_name`: `haproxy` (type: string)
- `profile_haproxy::config_dir`: `/etc/haproxy` (type: string)
- `profile_haproxy::config_file`: `/etc/haproxy/haproxy.cfg` (type: string)
- `profile_haproxy::service_name`: `haproxy` (type: string)
- `profile_haproxy::user`: `haproxy` (type: string)
- `profile_haproxy::group`: `haproxy` (type: string)
- `profile_haproxy::stats_enabled`: `true` (type: boolean) — note: cannot be cross-validated against structured analysis; asserted from Hiera data file content
- `profile_haproxy::stats_port`: `9000` (type: integer)
- `profile_haproxy::stats_uri`: `/haproxy-stats` (type: string)
- `profile_haproxy::stats_user`: `admin` (type: string)
- `profile_haproxy::stats_password`: `ENC[PKCS7,...]` (type: string — eyaml encrypted)
- `profile_haproxy::global_maxconn`: `4096` (type: integer)
- `profile_haproxy::client_timeout`: `30s` (type: string)
- `profile_haproxy::server_timeout`: `30s` (type: string)
- `profile_haproxy::connect_timeout`: `5s` (type: string)
- `profile_haproxy::retries`: `3` (type: integer)
- `profile_haproxy::ssl_enabled`: `false` (type: boolean)
- `profile_haproxy::ssl_cert_path`: `/etc/ssl/certs` (type: string)
- `profile_haproxy::ssl_key_path`: `/etc/ssl/private` (type: string)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256` (type: string)
- `profile_haproxy::ssl_min_version`: `TLSv1.2` (type: string)
- `profile_haproxy::log_server`: `127.0.0.1` (type: string)
- `profile_haproxy::log_facility`: `local0` (type: string)
- `profile_haproxy::log_level`: `info` (type: string)
- `profile_haproxy::backends`: hash with `webservers` and `api` keys (type: hash, deep-merge)

**`modules/profile_haproxy/data/environment/production.yaml` (L9)** → Migration note: Production environment overrides; map to `group_vars/production.yml`
- `profile_haproxy::global_maxconn`: `16384` (overrides common `4096`; itself overridden by cluster L3)
- `profile_haproxy::ssl_enabled`: `true` (overrides common `false`)
- `profile_haproxy::log_level`: `warning` (overrides common `info`)
- `profile_haproxy::client_timeout`: `60s` (overrides common `30s`)
- `profile_haproxy::server_timeout`: `60s` (overrides common `30s`)
- `profile_haproxy::stats_enabled`: `false` (overrides common `true`; itself overridden by node L1)
- `profile_haproxy::stick_table_enabled`: `true` (new key, not in common)
- `profile_haproxy::stick_table_size`: `200k` (new key)
- `profile_haproxy::stick_table_expire`: `30m` (new key)

**`modules/profile_haproxy/data/environment/staging.yaml` (L9)** → Migration note: Staging environment overrides; map to `group_vars/staging.yml`
- `profile_haproxy::global_maxconn`: `2048` (overrides common `4096`)
- `profile_haproxy::ssl_enabled`: `false` (same as common)
- `profile_haproxy::log_level`: `debug` (overrides common `info`)
- `profile_haproxy::stats_enabled`: `true` (same as common)
- `profile_haproxy::stick_table_enabled`: `false` (new key)

**`modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml` (L3 — beats environment L9)** → Migration note: Cluster-specific overrides; map to `group_vars/haproxy_prod_fra.yml`. **Critical**: In Ansible, `haproxy_prod_fra` group variables must be applied after `production` group variables to replicate this precedence. Document group ordering explicitly in inventory.
- `profile_haproxy::global_maxconn`: `32768` (overrides production L9 value of `16384`)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (overrides common AES128 suite)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (overrides common `TLSv1.2`)
- `profile_haproxy::backends`: adds `internal_monitoring` backend (deep-merged)

**`modules/profile_haproxy/data/datacenter/dc1_fra.yaml` (L11 — between environment L9 and OS L17)** → Migration note: Datacenter-specific overrides; map to `group_vars/dc1_fra.yml`. See hierarchy placement risk note above.
- `profile_haproxy::log_server`: `10.100.1.50` (overrides common `127.0.0.1`)
- `profile_haproxy::backends`: overrides server IPs for `webservers` and `api` to `10.100.x.x` range (deep-merged)

**`modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml` (L1 — highest priority)** → Migration note: Host-specific overrides; map to `host_vars/lb01.fra.example.com.yml`
- `profile_haproxy::stats_enabled`: `true` (overrides production L9 `false`)
- `profile_haproxy::stats_port`: `9001` (overrides common `9000`)
- `profile_haproxy::backends`: overrides `api1-fra` weight to `200` (deep-merged)

**`site/modules/linux/profile_haproxy/data/os/Debian.yaml` (L17)** → Migration note: Debian OS-specific variables; map to `group_vars/Debian.yml`
- `profile_haproxy::package_name`: `haproxy` (same as common — no effective change)
- `profile_haproxy::config_dir`: `/etc/haproxy` (same as common — no effective change)
- `profile_haproxy::firewall_provider`: `ufw` (OS-specific key)
- `profile_haproxy::extra_packages`: `['hatop']` (OS-specific key)
- `profile_haproxy::selinux_enabled`: not set (defaults to `false` in manifest lookup)

**`site/modules/linux/profile_haproxy/data/os/RedHat.yaml` (L17)** → Migration note: RedHat OS-specific variables; map to `group_vars/RedHat.yml`
- `profile_haproxy::package_name`: `haproxy` (same as common)
- `profile_haproxy::config_dir`: `/etc/haproxy` (same as common)
- `profile_haproxy::firewall_provider`: `firewalld` (OS-specific key)
- `profile_haproxy::firewall_zone`: `public` (OS-specific key)
- `profile_haproxy::extra_packages`: `['haproxy-systemd-wrapper', 'policycoreutils-python-utils']` (OS-specific key)
- `profile_haproxy::selinux_enabled`: `true` (OS-specific key)

**`site/modules/common/base_utils/data/common.yaml`** → Migration note: Base defaults for base_utils role; map to `defaults/main.yml` in base_utils Ansible role (separate from profile_haproxy defaults)
- `base_utils::manage_motd`: `true` (type: boolean)
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string)
- `base_utils::utility_packages`: `[]` (type: array — overridden by OS-level)

**`site/modules/common/base_utils/data/os/Debian.yaml`** → Migration note: Debian OS-specific packages for base_utils; map to `group_vars/Debian.yml`
- `base_utils::utility_packages`: `['vim', 'wget', 'curl', 'jq', 'dnsutils']`

**`site/modules/common/base_utils/data/os/RedHat.yaml`** → Migration note: RedHat OS-specific packages for base_utils; map to `group_vars/RedHat.yml`
- `base_utils::utility_packages`: `['vim-enhanced', 'wget', 'curl', 'jq', 'bind-utils']`

### Variable Migration Summary

- **Common defaults**: 25 variables from `profile_haproxy` common.yaml → `defaults/main.yml` (base configuration for all nodes)
- **base_utils common defaults**: 3 variables (manage_motd, motd_template, utility_packages) → separate `defaults/main.yml` in base_utils Ansible role
- **OS-specific variables**: 5 variables (Debian) + 6 variables (RedHat) from `profile_haproxy` OS files → `group_vars/Debian.yml`, `group_vars/RedHat.yml`
- **Environment-specific variables**: 9 variables (production) + 5 variables (staging) → `group_vars/production.yml`, `group_vars/staging.yml`
- **Cluster-specific variables**: 4 variables → `group_vars/haproxy_prod_fra.yml`
- **Datacenter-specific variables**: 2 variables → `group_vars/dc1_fra.yml`
- **Host-specific variables**: 3 variables → `host_vars/lb01.fra.example.com.yml`
- **Encrypted variables**: 1 variable (`profile_haproxy::stats_password`) → Ansible Vault in `group_vars/all/vault.yml`; never store in plaintext

### Cross-Level Overrides

- **`profile_haproxy::global_maxconn`**: defined at common (4096), production (16384), staging (2048), cluster/haproxy_prod_fra (32768); effective value for haproxy_prod_fra cluster = **32768** — cluster L3 beats environment L9; in Ansible, `haproxy_prod_fra` group must have higher precedence than `production` group
- **`profile_haproxy::stats_enabled`**: defined at common (true), production (false), staging (true), node lb01 (true); effective for lb01 = **true** — node L1 always wins; correctly replicated by Ansible `host_vars`
- **`profile_haproxy::stats_port`**: defined at common (9000), node lb01 (9001); effective = **9001**
- **`profile_haproxy::ssl_enabled`**: defined at common (false), production (true), staging (false); effective in production = **true**
- **`profile_haproxy::ssl_ciphers`**: defined at common (AES128 suite), cluster (AES256 suite); effective for haproxy_prod_fra = **AES256 suite**
- **`profile_haproxy::ssl_min_version`**: defined at common (TLSv1.2), cluster (TLSv1.3); effective for haproxy_prod_fra = **TLSv1.3**
- **`profile_haproxy::log_server`**: defined at common (127.0.0.1), datacenter dc1_fra (10.100.1.50); effective = **10.100.1.50**; merge strategy: first
- **`profile_haproxy::log_level`**: defined at common (info), production (warning), staging (debug); merge strategy: first
- **`profile_haproxy::backends`**: defined at common, datacenter, cluster, node; merge strategy: **deep** — all levels contribute, with higher-priority levels overriding specific keys within nested structures
- **`base_utils::utility_packages`**: defined at common ([]), Debian ([vim,wget,curl,jq,dnsutils]), RedHat ([vim-enhanced,wget,curl,jq,bind-utils]); merge strategy: first

### Merge Strategy Notes

- Variables using `deep` merge — Hash values are recursively merged (deep merge): `profile_haproxy::backends`
- Variables using `first` (default) — First value found wins, no merging: all scalar variables (`global_maxconn`, `ssl_enabled`, `log_level`, `log_server`, `stats_enabled`, `stats_port`, `utility_packages`, etc.)

---

## Custom Types and Providers

### `puppetdb_query` function (`modules/puppetdb_query_stub/lib/puppet/functions/puppetdb_query.rb`)

- **Type**: Ruby Puppet function (4.x API, `Puppet::Functions.create_function`)
- **Signature**: `puppetdb_query(String $pql) → Array`
- **Behavior**: Unconditionally returns `[]` (empty Array) and emits `Puppet.warning(...)`. Does NOT connect to PuppetDB. This is a CI/standalone-catalog stub.
- **Effect on execution**: The `$app_servers` variable in `profile_haproxy::discover` is always `[]`, so the dynamic backend loop never runs. All backends are effectively static (from Hiera).
- **Ansible equivalent**:
  - To replicate stub behavior: use `set_fact: app_servers: []` or `default([])` filter — no custom module needed.
  - To replicate real PuppetDB behavior: use `community.general` lookup plugin `puppetdb` targeting the PuppetDB REST API (`GET /pdb/query/v4`), or write a custom lookup plugin hitting `https://<puppetdb>:8081/pdb/query/v4` with the PQL query.
  - **Recommended migration approach**: Replace with static Ansible inventory group `app_servers`; iterate `groups['app_servers']` in the HAProxy backend template to build the `api` backend server list dynamically from inventory.

### `base_utils::normalize_port` function

- **Type**: Custom Puppet function defined in the `base_utils` module (not from `puppetlabs-stdlib`)
- **Usage**: Called in `profile_haproxy::firewall` as `base_utils::normalize_port($profile_haproxy::stats_port)` to normalize `9001` to Integer `9001`
- **Ansible equivalent**: Use Jinja2 `| int` filter or `ansible.builtin.set_fact` with explicit integer casting

---

## Dependencies

**External module dependencies**:
- `puppetlabs-stdlib` 9.7.0 — provides `empty()`, `lookup()` helpers
- `puppetlabs-concat` 9.0.2 — declared but not directly used in this execution path
- `puppetlabs-firewall` 8.1.3 — declared but not used in this path (firewall managed via `exec` resources directly)
- `puppetlabs-vcsrepo` 6.1.0 — not used in this execution path
- `puppet-redis` 11.0.0 — not used in this execution path
- `puppetlabs-apt` 9.4.0 — not used in this execution path

**System package dependencies**:
- `haproxy` (all OS)
- `hatop` (Debian only — extra package)
- `haproxy-systemd-wrapper`, `policycoreutils-python-utils` (RedHat only — extra packages)
- `ufw` (Debian only — firewall)
- `chrony` (all Linux — NTP)
- `rsyslog` (all Linux — syslog)
- `vim` / `vim-enhanced`, `wget`, `curl`, `jq`, `dnsutils` / `bind-utils` (OS-specific utility packages)

**Service dependencies** (ordering):
- `profile_haproxy::install` → `profile_haproxy::config` → `profile_haproxy::discover` ~> `profile_haproxy::service`
- `profile_haproxy::firewall` runs in parallel (no explicit ordering to firewall class)
- `profile::base::base` → `profile::loadbalancer::haproxy` (base OS must complete before HAProxy)
- Config file change → config validation exec → service restart (notification chain)

---

## Puppet Facts Used

- `$facts['kernel']` — determines if Linux-specific resources (chrony, rsyslog, global exec path) are applied; always `'Linux'` on target nodes
- `$facts['kernel'].downcase` — used in `role::haproxy` for `== 'linux'` comparison
- `$facts['networking']['fqdn']` — used in `profile_haproxy::discover` as the exported balancermember title and `server_names` value
- `$facts['networking']['ip']` — used in `profile_haproxy::discover` as the exported balancermember `ipaddresses` value
- `$facts['puppet_environment']` — used in the PuppetDB PQL query to scope app server discovery to the current Puppet environment (intercepted by stub, never actually evaluated)
- `fact('environment')` — used in `profile::loadbalancer::haproxy` to set `$environment_name` (informational only, not passed downstream)

---

## Template Conversion Notes

### `profile_haproxy/haproxy.cfg.erb` (ERB, rendered once per node)
- Variables used: `@global_maxconn`, `@log_server`, `@log_facility`, `@log_level`, `@client_timeout`, `@server_timeout`, `@connect_timeout`, `@retries`, `@ssl_enabled`, `@ssl_cert_path`, `@ssl_key_path`, `@ssl_ciphers`, `@ssl_min_version`, `@stats_enabled`, `@stats_port`, `@stats_uri`, `@stats_user`, `@stats_password`
- `@stats_password` is a `Sensitive` type — must call `.unwrap` in ERB to access the plaintext value
- Conditional rendering: SSL bind directives only if `@ssl_enabled == true`; stats section only if `@stats_enabled == true`
- **Ansible conversion**: Jinja2 template; use `{{ haproxy_stats_password }}` sourced from Ansible Vault; use `{% if haproxy_ssl_enabled %}` blocks for conditional sections

### `profile_haproxy/backend.conf.epp` (EPP, rendered 3 times — once per backend)
- Variables used: `$backend_name`, `$balance`, `$port`, `$servers` (array of hashes with `name`, `address`, `weight`), `$health_check`, `$health_interval`, `$ssl_enabled`
- Iteration: loops over `$servers` array to emit `server <name> <address>:<port> weight <weight> check` lines
- Conditional: SSL-specific options appended to server lines if `$ssl_enabled == true`
- Rendered for: `webservers` (3 servers), `api` (2 servers), `internal_monitoring` (1 server)
- **Ansible conversion**: Jinja2 template with `{% for server in backend.servers %}` loop; render once per backend using `loop` over `haproxy_backends` dict

---

## PuppetDB Dependencies

### Exported Resources
- `@@haproxy::balancermember[$facts['networking']['fqdn']]` in `profile_haproxy::discover`:
  - Exports this node's membership into PuppetDB with `listening_service: 'webservers'`, `server_names: <node FQDN>`, `ipaddresses: <node IP>`, `ports: '8080'`, `options: 'check'`
  - **Migration note**: No direct Ansible equivalent. Replace with static inventory group membership. Each web server node should be in an Ansible group (e.g., `webservers`) and the HAProxy role should iterate `groups['webservers']` to build the backend. This is a cross-node data sharing pattern — the HAProxy node must have access to web server inventory data at playbook runtime.

### Resource Collectors
- `Haproxy::Balancermember <<| listening_service == 'webservers' |>>` in `profile_haproxy::discover`:
  - Realizes all exported `haproxy::balancermember` resources tagged for the `webservers` service from PuppetDB. With the stub active, this collector realizes zero resources.
  - **Migration note**: Replace with static `haproxy_backends.webservers.servers` list in `group_vars` or dynamic inventory group iteration over `groups['webservers']`. This collector is the counterpart to the exported resource above — both must be migrated together. Note: this pattern is entirely separate from the `api` backend population (which uses a direct PuppetDB query loop, not export/collect).

### PuppetDB Queries
- Query in `profile_haproxy::discover`: `resources[certname, parameters] { type = 'Class' and title = 'Profile::App_server' and certname in resources[certname] { type = 'Class' and title = 'Profile::Base' and parameters.environment = '${facts['puppet_environment']}' } }`
  - Returns all nodes classified with `Profile::App_server` in the same Puppet environment
  - **STUB ACTIVE**: Always returns `[]`. No app servers are dynamically added to the `api` backend via this path.
  - **Migration note**: Replace with `groups['app_servers'] | map(attribute='inventory_hostname')` or a static list in `haproxy_backends.api.servers`. If live PuppetDB querying is needed, use `community.general.puppetdb` lookup plugin or a custom lookup against `GET /pdb/query/v4`. This query populates the `api` backend via direct resource creation (not export/collect) — distinct from the `webservers` export/collect pattern.

---

## Checks for the Migration

**Files to verify after migration**:
- `/etc/haproxy/haproxy.cfg` — main config
- `/etc/haproxy/conf.d/webservers.cfg` — webservers backend fragment
- `/etc/haproxy/conf.d/api.cfg` — api backend fragment
- `/etc/haproxy/conf.d/internal_monitoring.cfg` — internal monitoring backend fragment (haproxy_prod_fra cluster only)
- `/etc/haproxy/conf.d/stick-tables.cfg` — stick table config (production only)
- `/etc/haproxy/errors/503.http` — custom 503 error page
- `/etc/haproxy/errors/408.http` — custom 408 error page
- `/etc/logrotate.d/haproxy` — logrotate config
- `/etc/motd` — MOTD file
- `/var/lib/haproxy/` — HAProxy runtime directory (owner: haproxy, mode: 0750)
- `/etc/haproxy/conf.d/` — backend config directory (owner: root:haproxy, mode: 0755)
- `/etc/haproxy/errors/` — error pages directory (owner: root:haproxy, mode: 0755)

**Service endpoints to check**:
- HTTP: port `80` (firewall open)
- HTTPS: port `443` (firewall open)
- HAProxy stats: port `9001` at `/haproxy-stats` (lb01.fra.example.com only; authenticate with `admin` / vault password)
- Backend health — webservers: port `8080`, api: port `3000`, internal_monitoring: port `9090`

**Templates rendered**:
- `haproxy.cfg.erb` → `/etc/haproxy/haproxy.cfg` (1 render per node)
- `backend.conf.epp` → `/etc/haproxy/conf.d/webservers.cfg` (1 render)
- `backend.conf.epp` → `/etc/haproxy/conf.d/api.cfg` (1 render)
- `backend.conf.epp` → `/etc/haproxy/conf.d/internal_monitoring.cfg` (1 render, haproxy_prod_fra only)

## Pre-flight checks:
```bash
# HAProxy config validation
haproxy -c -f /etc/haproxy/haproxy.cfg

# Service status
systemctl status haproxy
systemctl is-enabled haproxy

# Base OS services
systemctl status chronyd
systemctl status rsyslog

# HAProxy user/group
id haproxy
# Expected: uid=<n>(haproxy) gid=<n>(haproxy) groups=<n>(haproxy), shell=/sbin/nologin

# Directory ownership and permissions
stat /var/lib/haproxy
# Expected: owner haproxy:haproxy, mode 0750
stat /etc/haproxy/conf.d
# Expected: owner root:haproxy, mode 0755
stat /etc/haproxy/errors
# Expected: owner root:haproxy, mode 0755

# Backend config fragments
test -f /etc/haproxy/conf.d/webservers.cfg && echo "webservers.cfg present"
test -f /etc/haproxy/conf.d/api.cfg && echo "api.cfg present"
test -f /etc/haproxy/conf.d/internal_monitoring.cfg && echo "internal_monitoring.cfg present"
test -f /etc/haproxy/conf.d/stick-tables.cfg && echo "stick-tables.cfg present"  # production only

# Error pages
test -f /etc/haproxy/errors/503.http && echo "503.http present"
test -f /etc/haproxy/errors/408.http && echo "408.http present"

# Logrotate
test -f /etc/logrotate.d/haproxy && echo "logrotate config present"

# Stats endpoint (lb01.fra.example.com only)
curl -u admin:<stats_password> http://lb01.fra.example.com:9001/haproxy-stats

# Firewall — Debian (ufw)
ufw status
# Expected: Status: active, 80/tcp ALLOW, 443/tcp ALLOW, 9001/tcp ALLOW (lb01 only)

# Firewall — RedHat (firewalld)
firewall-cmd --zone=public --list-ports
# Expected: 80/tcp 443/tcp 9001/tcp (lb01 only)

# SELinux — RedHat only
getsebool haproxy_connect_any
# Expected: haproxy_connect_any --> on

# Backend connectivity checks
# webservers backend
curl -sf http://10.100.1.10:8080/health && echo "web1-fra healthy"
curl -sf http://10.100.1.11:8080/health && echo "web2-fra healthy"
curl -sf http://10.100.1.12:8080/health && echo "web3-fra healthy"

# api backend
curl -sf http://10.100.2.10:3000/api/health && echo "api1-fra healthy"
curl -sf http://10.100.2.11:3000/api/health && echo "api2-fra healthy"

# internal_monitoring backend (haproxy_prod_fra only)
curl -sf http://10.100.3.10:9090/-/healthy && echo "prom1-fra healthy"

# SSL certificate paths
test -d /etc/ssl/certs && echo "ssl_cert_path present"
test -d /etc/ssl/private && echo "ssl_key_path present"
# Note: TLS key material is managed outside Puppet/Ansible
# Ensure certificate deployment runs before HAProxy role
```