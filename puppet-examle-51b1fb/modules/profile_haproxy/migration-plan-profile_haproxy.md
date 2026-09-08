---
source-path: site/modules/linux/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module deploys and manages HAProxy as a load balancer on Linux systems. It installs the HAProxy package, writes a main configuration file and per-backend config fragments, manages firewall rules (firewalld on RedHat, ufw on Debian), configures log rotation, and uses PuppetDB exported resources to dynamically discover backend members. The module is driven by a rich Hiera hierarchy spanning 8 levels (common → OS family → datacenter → environment → cluster → node), with deep-merged backend definitions and one eyaml-encrypted credential (stats password). The effective production configuration for node `lb01.fra.example.com` in the `haproxy_prod_fra` cluster results in 3 backends, TLSv1.3-only SSL, 32768 max connections, and stats re-enabled on port 9001.

## Service Type and Instances

**Service Type**: Load Balancer (HAProxy)

**Configured Instances** (effective values for `lb01.fra.example.com` / `haproxy_prod_fra` cluster / `dc1_fra` datacenter / `production` environment):

- **webservers backend**: HTTP round-robin load balancing to web tier
  - Port: `8080`
  - Balance: `roundrobin`
  - Health check: `httpchk GET /health` every `5s`
  - Servers: `web1-fra` (10.100.1.10:8080 w=100), `web2-fra` (10.100.1.11:8080 w=100), `web3-fra` (10.100.1.12:8080 w=100)

- **api backend**: HTTP least-connections load balancing to API tier
  - Port: `3000`
  - Balance: `leastconn`
  - Health check: `httpchk GET /api/health` every `10s`
  - Servers: `api1-fra` (10.100.2.10:3000 w=200), `api2-fra` (10.100.2.11:3000 w=100) — asymmetric weights from node-level override

- **internal_monitoring backend**: Prometheus scrape target (cluster-only, `haproxy_prod_fra`)
  - Port: `9090`
  - Balance: `roundrobin`
  - Health check: `httpchk GET /-/healthy` every `15s`
  - Servers: `prom1-fra` (10.100.3.10:9090 w=100)

- **HAProxy stats UI**: enabled on `lb01.fra.example.com` only (node-level override)
  - Port: `9001` (node override from common default `9000`)
  - URI: `/haproxy-stats`
  - User: `admin` / password: `[ENCRYPTED — eyaml PKCS7, must be decrypted and stored in ansible-vault]`

## File Structure

```
site/
├── role/
│   └── manifests/
│       └── haproxy.pp
├── profile/
│   └── manifests/
│       ├── loadbalancer/
│       │   └── haproxy.pp
│       └── base/
│           └── base.pp
└── modules/
    ├── linux/
    │   └── profile_haproxy/
    │       ├── manifests/
    │       │   ├── init.pp
    │       │   ├── install.pp
    │       │   ├── config.pp
    │       │   ├── discover.pp
    │       │   ├── service.pp
    │       │   └── firewall.pp
    │       ├── templates/
    │       │   ├── haproxy.cfg.erb
    │       │   └── backend.conf.epp
    │       ├── data/
    │       │   ├── common.yaml
    │       │   ├── os/
    │       │   │   ├── Debian.yaml
    │       │   │   └── RedHat.yaml
    │       │   ├── datacenter/
    │       │   │   └── dc1_fra.yaml
    │       │   ├── environment/
    │       │   │   ├── production.yaml
    │       │   │   └── staging.yaml
    │       │   ├── cluster/
    │       │   │   └── haproxy_prod_fra.yaml
    │       │   └── nodes/
    │       │       └── lb01.fra.example.com.yaml
    │       └── lib/
    │           └── facter/
    │               └── haproxy_version.rb
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

## Module Explanation

The module performs operations in this order:

1. **role::haproxy** (`site/role/manifests/haproxy.pp`):
   - Conditional: `if $facts['kernel'].downcase == 'linux'` → runs `exec 'default'` (kernel guard)
   - `include ::profile::base::base` (no containment — ordering via `->`)
   - `include ::profile::loadbalancer::haproxy`
   - Sets ordering: `Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']`

2. **::profile::base::base** (`site/profile/manifests/base/base.pp`):
   - Conditional: `if $manage_utils` (true by default) → includes `base_utils` (see step 2a)
   - Conditional: `if $manage_ntp and $facts['kernel'] == 'Linux'` (both true):
     - `package 'chrony'` → ensure: `present`
     - `service 'chronyd'` → ensure: `running`, enable: `true`
   - Conditional: `if $manage_syslog and $facts['kernel'] == 'Linux'` (both true):
     - `package 'rsyslog'` → ensure: `present`
     - `service 'rsyslog'` → ensure: `running`, enable: `true`

   **2a. base_utils** (`site/modules/common/base_utils/manifests/init.pp`):
   - Conditional: `if $manage_motd` (true — from `base_utils::manage_motd: true`):
     - `file '/etc/motd'` → content from template `base_utils/motd.erb`
   - Loop: `$utility_packages.each |$pkg|` — expanded per OS family:
     - **Debian** (5 iterations): `package 'vim'`, `package 'wget'`, `package 'curl'`, `package 'jq'`, `package 'dnsutils'` → each ensure: `present`
     - **RedHat** (5 iterations): `package 'vim-enhanced'`, `package 'wget'`, `package 'curl'`, `package 'jq'`, `package 'bind-utils'` → each ensure: `present`

3. **::profile::loadbalancer::haproxy** (`site/profile/manifests/loadbalancer/haproxy.pp`):
   - Reads fact: `fact('environment')` (e.g., `production`)
   - Includes `profile_haproxy` (see step 4)

4. **profile_haproxy** (`site/modules/linux/profile_haproxy/manifests/init.pp`):
   - Resolves all class parameters from Hiera (see Variables section)
   - `contain profile_haproxy::install`
   - `contain profile_haproxy::config`
   - `contain profile_haproxy::discover`
   - `contain profile_haproxy::service`
   - `contain profile_haproxy::firewall`
   - Sets ordering:
     - `Class['profile_haproxy::install'] -> Class['profile_haproxy::config']`
     - `Class['profile_haproxy::config'] -> Class['profile_haproxy::discover']`
     - `Class['profile_haproxy::discover'] ~> Class['profile_haproxy::service']` (notify — service restarts if discover changes)

5. **profile_haproxy::install** (`site/modules/linux/profile_haproxy/manifests/install.pp`):
   - `package 'haproxy'` → ensure: `present`
   - Conditional: `if !empty($extra_packages)` — expanded per OS family:
     - **Debian** (`$extra_packages = ['hatop']`, 1 iteration):
       - `package 'hatop'` → ensure: `present`
     - **RedHat** (`$extra_packages = ['haproxy-systemd-wrapper', 'policycoreutils-python-utils']`, 2 iterations):
       - `package 'haproxy-systemd-wrapper'` → ensure: `present`
       - `package 'policycoreutils-python-utils'` → ensure: `present`
   - `group 'haproxy'` → ensure: `present`
   - `user 'haproxy'` → ensure: `present`, gid: `haproxy`, shell: `/sbin/nologin`
   - `file ['/etc/haproxy', '/etc/haproxy/conf.d']` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0755`
   - `file '/var/lib/haproxy'` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0755`
   - Conditional: `if $selinux_enabled`:
     - **Debian**: `$selinux_enabled = false` → skipped
     - **RedHat**: `$selinux_enabled = true` → `exec 'haproxy_selinux_connect'` → command: `setsebool -P haproxy_connect_any 1`, unless: `getsebool haproxy_connect_any | grep -q on`

6. **profile_haproxy::config** (`site/modules/linux/profile_haproxy/manifests/config.pp`):
   - `file '/etc/haproxy/haproxy.cfg'` (template `profile_haproxy/haproxy.cfg.erb`) → owner: `root`, group: `haproxy`, mode: `0640`
     - Template variables (19 variables, 3 logic blocks — see Template Conversion Notes):
       - `log_server` = `10.100.1.50` (dc1_fra override)
       - `log_facility` = `local0`
       - `log_level` = `warning` (production override)
       - `global_maxconn` = `32768` (cluster haproxy_prod_fra wins)
       - `client_timeout` = `60s` (production override)
       - `server_timeout` = `60s` (production override)
       - `connect_timeout` = `5s` (common default)
       - `retries` = `3`
       - `ssl_enabled` = `true` (production override)
       - `ssl_cert_path` = `/etc/ssl/certs`
       - `ssl_key_path` = `/etc/ssl/private`
       - `ssl_ciphers` = `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (cluster override)
       - `ssl_min_version` = `TLSv1.3` (cluster override)
       - `stats_enabled` = `true` (node lb01 override wins over production false)
       - `stats_port` = `9001` (node lb01 override)
       - `stats_uri` = `/haproxy-stats`
       - `stats_user` = `admin`
       - `stats_password` = `[ENCRYPTED — eyaml PKCS7, must be decrypted and stored in ansible-vault]`
       - `stick_table_enabled` = `true` (production override)
       - Note: `stick_table_size` and `stick_table_expire` are also rendered inside logic block 3 but may not be counted separately in the 19-variable total; verify against template source (see Template Conversion Notes)

   - Loop: `$profile_haproxy::backends.each |$backend_name, $backend_config|` — runs **3 times** for `lb01.fra.example.com` in `haproxy_prod_fra`:

     - **webservers**:
       - `file '/etc/haproxy/conf.d/webservers.cfg'` (template `profile_haproxy/backend.conf.epp`) → owner: `root`, group: `haproxy`, mode: `0640`
         - `backend_name` = `webservers`
         - `balance` = `roundrobin`
         - `port` = `8080`
         - `health_check` = `httpchk GET /health`
         - `health_interval` = `5s`
         - `servers` = `[{name: web1-fra, address: 10.100.1.10, weight: 100}, {name: web2-fra, address: 10.100.1.11, weight: 100}, {name: web3-fra, address: 10.100.1.12, weight: 100}]`

     - **api**:
       - `file '/etc/haproxy/conf.d/api.cfg'` (template `profile_haproxy/backend.conf.epp`) → owner: `root`, group: `haproxy`, mode: `0640`
         - `backend_name` = `api`
         - `balance` = `leastconn`
         - `port` = `3000`
         - `health_check` = `httpchk GET /api/health`
         - `health_interval` = `10s`
         - `servers` = `[{name: api1-fra, address: 10.100.2.10, weight: 200}, {name: api2-fra, address: 10.100.2.11, weight: 100}]` (node-level weight override applied)

     - **internal_monitoring**:
       - `file '/etc/haproxy/conf.d/internal_monitoring.cfg'` (template `profile_haproxy/backend.conf.epp`) → owner: `root`, group: `haproxy`, mode: `0640`
         - `backend_name` = `internal_monitoring`
         - `balance` = `roundrobin`
         - `port` = `9090`
         - `health_check` = `httpchk GET /-/healthy`
         - `health_interval` = `15s`
         - `servers` = `[{name: prom1-fra, address: 10.100.3.10, weight: 100}]`

   - Loop: `['503', '408'].each |$code|` — runs **2 times**:
     - **503**: `file '/etc/haproxy/errors/503.http'` → ensure: `present`, source: `profile_haproxy/files/errors/503.http`
     - **408**: `file '/etc/haproxy/errors/408.http'` → ensure: `present`, source: `profile_haproxy/files/errors/408.http`

   - `file '/etc/haproxy/errors'` → ensure: `directory`, owner: `root`, group: `haproxy`, mode: `0755`

   - Conditional: `if $stick_table_enabled`:
     - **production** (`$stick_table_enabled = true`): `file '/etc/haproxy/conf.d/stick-tables.cfg'` → content: stick-table config with `size: 200k`, `expire: 30m`
     - **staging** (`$stick_table_enabled = false`): skipped
     - ⚠️ **Validation note**: `stick_table_enabled`, `stick_table_size`, and `stick_table_expire` have no documented `common.yaml` default. Nodes outside production/staging environments will have an undefined variable and may fail catalog compilation. Recommend adding `profile_haproxy::stick_table_enabled: false` (and corresponding size/expire defaults) to `common.yaml`, or explicitly scoping these variables to environment-level Hiera only with a documented caveat.

7. **profile_haproxy::discover** (`site/modules/linux/profile_haproxy/manifests/discover.pp`):

   ⚠️ **PuppetDB-dependent** — this class uses exported resources and PuppetDB queries. There is no direct Ansible equivalent; dynamic inventory or a service registry (Consul, etcd) must replace this pattern.

   - Exported resource `@@haproxy::balancermember[$facts['networking']['fqdn']]`:
     - `listening_service`: `webservers`
     - `server_names`: `$facts['networking']['fqdn']` (e.g., `lb01.fra.example.com`)
     - `ipaddresses`: `$facts['networking']['ip']`
     - `ports`: `8080`
     - `options`: `check`

   - Resource collector `Haproxy::Balancermember <| listening_service == 'webservers' |>`:
     - Realizes all exported `haproxy::balancermember` resources tagged with `listening_service == 'webservers'` from PuppetDB
     - Dynamically populates the webservers backend with all nodes that have exported themselves

   - PuppetDB query populates `$app_servers`:
     - Query (inferred from manifest source — not confirmed by execution tree alone): `resources[certname, parameters] { type = 'Class' and title = 'Profile::App_server' and certname in resources[certname] { type = 'Class' and title = 'Profile::Base' and parameters.environment = '${facts['puppet_environment']}' } }`
     - Purpose: discovers all nodes classified with `Profile::App_server` in the same Puppet environment

   - Loop: `$app_servers.each |$server|` — runs N times (one per discovered app server node):
     - `haproxy::balancermember "api-${certname}"`:
       - `listening_service`: `api`
       - `server_names`: `$server['certname']`
       - `ipaddresses`: `$server['parameters']['ip']`
       - `ports`: `3000`
       - `options`: `check`

8. **profile_haproxy::service** (`site/modules/linux/profile_haproxy/manifests/service.pp`):
   - `exec 'haproxy_config_check'` → command: `/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg`, refreshonly: `true`
   - `service 'haproxy'` → ensure: `running`, enable: `true`, hasstatus: `true`, hasrestart: `true`
   - `file '/etc/logrotate.d/haproxy'` → owner: `root`, group: `root`, mode: `0644`, content: logrotate config for `/var/log/haproxy.log`
   - Notification/ordering chain:
     - `File['/etc/haproxy/haproxy.cfg'] ~> Exec['haproxy_config_check']` (config change triggers validation)
     - `Exec['haproxy_config_check'] -> Service['haproxy']` (validation must pass before service action)
     - `File['/etc/haproxy/haproxy.cfg'] ~> Service['haproxy']` (config change also notifies service restart)

9. **profile_haproxy::firewall** (`site/modules/linux/profile_haproxy/manifests/firewall.pp`):

   - Conditional: `case $firewall_provider`

   - **Branch `firewalld`** (RedHat — `$firewall_provider = 'firewalld'`, `$firewall_zone = 'public'`):
     - Opens HTTP (port 80) in zone `public` via firewalld
     - Opens HTTPS (port 443) in zone `public` via firewalld
     - Conditional: if `$stats_enabled = true` → opens stats port `9001` in zone `public`
     - `exec 'firewalld_reload'` → command: `firewall-cmd --reload`, refreshonly: `true`
     - ⚠️ **Validation note**: The execution tree only confirms `exec[firewalld_reload]` as a named resource. Individual port-open operations may use a `firewalld_port` or `firewalld_service` resource type from a Puppet firewalld module rather than bare `exec` resources. Verify against `firewall.pp` source.

   - **Branch `ufw`** (Debian — `$firewall_provider = 'ufw'`):
     - `package 'ufw'` → ensure: `present`
     - `exec 'ufw_allow_http'` → command: `ufw allow 80/tcp`, unless: `ufw status | grep -q '80/tcp'`
     - `exec 'ufw_allow_https'` → command: `ufw allow 443/tcp`, unless: `ufw status | grep -q '443/tcp'`
     - Conditional: if `$stats_enabled = true` → `exec 'ufw_allow_stats'` → command: `ufw allow 9001/tcp`
     - `exec 'ufw_enable'` → command: `ufw --force enable`, unless: `ufw status | grep -q 'Status: active'`
     - ⚠️ **Validation note**: `exec[ufw_allow_stats]` is not listed in the execution tree. Verify against `firewall.pp` source that this conditional resource exists as described.

   - **Branch `default`** (unknown provider):
     - `notify 'Unknown firewall provider: ${firewall_provider}'` → emits a Puppet warning message

## Variables

**Variable Flow Summary**: 35+ variables across 8 Hiera levels (common → OS family → datacenter → environment → cluster → node), with `backends` hash using deep merge strategy across all levels.

### Variable Definitions

**common.yaml (module defaults — lowest priority)** → Migration note: Base defaults for all nodes; maps to `defaults/main.yml`
- `profile_haproxy::package_name`: `haproxy` (type: string)
- `profile_haproxy::config_dir`: `/etc/haproxy` (type: string)
- `profile_haproxy::config_file`: `/etc/haproxy/haproxy.cfg` (type: string)
- `profile_haproxy::service_name`: `haproxy` (type: string)
- `profile_haproxy::user`: `haproxy` (type: string)
- `profile_haproxy::group`: `haproxy` (type: string)
- `profile_haproxy::stats_enabled`: `true` (type: boolean)
- `profile_haproxy::stats_port`: `9000` (type: integer)
- `profile_haproxy::stats_uri`: `/haproxy-stats` (type: string)
- `profile_haproxy::stats_user`: `admin` (type: string)
- `profile_haproxy::stats_password`: `ENC[PKCS7,...]` (type: string — **ENCRYPTED**, must be decrypted from eyaml PKCS7 and re-encrypted with `ansible-vault`)
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
- `profile_haproxy::backends`: `{webservers: {...}, api: {...}}` (type: hash — deep merge base)
- ⚠️ **Validation note**: `profile_haproxy::stick_table_enabled`, `profile_haproxy::stick_table_size`, and `profile_haproxy::stick_table_expire` are not documented here but are referenced in config.pp conditionals. Recommend adding `profile_haproxy::stick_table_enabled: false`, `profile_haproxy::stick_table_size: 100k`, and `profile_haproxy::stick_table_expire: 10m` as safe defaults to prevent catalog failures on nodes outside production/staging.

**os/Debian.yaml** → Migration note: OS-specific variables, loaded conditionally based on OS family; maps to `group_vars/Debian.yml`
- `profile_haproxy::package_name`: `haproxy` (redundant override)
- `profile_haproxy::config_dir`: `/etc/haproxy` (redundant override)
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::extra_packages`: `['hatop']` (type: array)
- `profile_haproxy::selinux_enabled`: `false` (type: boolean)

**os/RedHat.yaml** → Migration note: OS-specific variables, loaded conditionally based on OS family; maps to `group_vars/RedHat.yml`
- `profile_haproxy::package_name`: `haproxy` (redundant override)
- `profile_haproxy::config_dir`: `/etc/haproxy` (redundant override)
- `profile_haproxy::firewall_provider`: `firewalld` (type: string)
- `profile_haproxy::firewall_zone`: `public` (type: string)
- `profile_haproxy::extra_packages`: `['haproxy-systemd-wrapper', 'policycoreutils-python-utils']` (type: array)
- `profile_haproxy::selinux_enabled`: `true` (type: boolean)

**datacenter/dc1_fra.yaml** → Migration note: Datacenter-specific variables; maps to `group_vars/dc1_fra.yml`
- `profile_haproxy::log_server`: `10.100.1.50` (overrides common `127.0.0.1`)
- `profile_haproxy::ntp_servers`: `['ntp1.dc1.fra.example.com', 'ntp2.dc1.fra.example.com']` (type: array — ⚠️ not referenced in any profile_haproxy manifest or template; may belong to a different module's namespace or be consumed by a cross-module profile; verify before migrating)
- `profile_haproxy::backends`: partial deep-merge — replaces `webservers.servers` and `api.servers` with Frankfurt IPs

**environment/production.yaml** → Migration note: Production environment overrides; maps to `group_vars/production.yml`
- `profile_haproxy::global_maxconn`: `16384` (overrides common `4096`; further overridden by cluster to `32768`)
- `profile_haproxy::ssl_enabled`: `true` (overrides common `false`)
- `profile_haproxy::log_level`: `warning` (overrides common `info`)
- `profile_haproxy::client_timeout`: `60s` (overrides common `30s`)
- `profile_haproxy::server_timeout`: `60s` (overrides common `30s`)
- `profile_haproxy::stats_enabled`: `false` (overrides common `true`; further overridden by node lb01 to `true`)
- `profile_haproxy::stick_table_enabled`: `true` (type: boolean — introduced at this level)
- `profile_haproxy::stick_table_size`: `200k` (type: string — introduced at this level)
- `profile_haproxy::stick_table_expire`: `30m` (type: string — introduced at this level)

**environment/staging.yaml** → Migration note: Staging environment overrides; maps to `group_vars/staging.yml`
- `profile_haproxy::global_maxconn`: `2048` (overrides common `4096` — resource-constrained)
- `profile_haproxy::ssl_enabled`: `false` (redundant — same as common)
- `profile_haproxy::log_level`: `debug` (overrides common `info`)
- `profile_haproxy::stats_enabled`: `true` (redundant — same as common)
- `profile_haproxy::stick_table_enabled`: `false` (type: boolean — introduced at this level)

**cluster/haproxy_prod_fra.yaml** → Migration note: Cluster-specific overrides for Frankfurt production HAProxy cluster; maps to `group_vars/haproxy_prod_fra.yml`
- `profile_haproxy::global_maxconn`: `32768` (overrides both common `4096` and production `16384` — **effective winner**)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (overrides common AES128 suite)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (overrides common `TLSv1.2`)
- `profile_haproxy::backends`: partial deep-merge — adds `internal_monitoring` backend key only

**nodes/lb01.fra.example.com.yaml (highest priority)** → Migration note: Host-specific overrides; maps to `host_vars/lb01.fra.example.com.yml`
- `profile_haproxy::stats_enabled`: `true` (overrides production `false` — node-level exception)
- `profile_haproxy::stats_port`: `9001` (overrides common `9000`)
- `profile_haproxy::backends`: partial deep-merge — overrides `api.servers` weights only (api1-fra w=200, api2-fra w=100)

**base_utils/data/common.yaml** → Migration note: Base utility defaults for all nodes
- `base_utils::manage_motd`: `true` (type: boolean)
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string)
- `base_utils::utility_packages`: `[]` (type: array — overridden at OS level)

**base_utils/data/os/Debian.yaml** → Migration note: Debian-specific utility packages
- `base_utils::utility_packages`: `['vim', 'wget', 'curl', 'jq', 'dnsutils']` (type: array)

**base_utils/data/os/RedHat.yaml** → Migration note: RedHat-specific utility packages
- `base_utils::utility_packages`: `['vim-enhanced', 'wget', 'curl', 'jq', 'bind-utils']` (type: array)

### Variable Migration Summary

- **Common defaults**: 25 variables from `common.yaml` → `defaults/main.yml` (base configuration for all nodes)
- **OS-specific (Debian)**: 5 variables → `group_vars/Debian.yml`
- **OS-specific (RedHat)**: 6 variables → `group_vars/RedHat.yml`
- **Datacenter-specific**: 3 variables from `datacenter/dc1_fra.yaml` → `group_vars/dc1_fra.yml`
- **Environment-specific (production)**: 9 variables → `group_vars/production.yml`
- **Environment-specific (staging)**: 5 variables → `group_vars/staging.yml`
- **Cluster-specific**: 4 variables from `cluster/haproxy_prod_fra.yaml` → `group_vars/haproxy_prod_fra.yml`
- **Host-specific**: 3 variables from `nodes/lb01.fra.example.com.yaml` → `host_vars/lb01.fra.example.com.yml`
- **Encrypted**: 1 variable (`stats_password`) — must be decrypted from eyaml PKCS7 and re-encrypted with `ansible-vault`

### Cross-Level Overrides

Variables defined at multiple Hiera levels (merge strategy: `first` unless noted):

- **`global_maxconn`**: common (`4096`) → production (`16384`) → cluster `haproxy_prod_fra` (`32768`); staging (`2048`). Effective: `32768` for haproxy_prod_fra, `2048` for staging, `16384` for other production nodes.
- **`ssl_enabled`**: common (`false`) → production (`true`), staging (`false`). Effective: `true` in production.
- **`ssl_ciphers`**: common (AES128 suite) → cluster `haproxy_prod_fra` (AES256 suite). Effective: AES256 for haproxy_prod_fra.
- **`ssl_min_version`**: common (`TLSv1.2`) → cluster `haproxy_prod_fra` (`TLSv1.3`). Effective: `TLSv1.3` for haproxy_prod_fra.
- **`log_server`**: common (`127.0.0.1`) → datacenter `dc1_fra` (`10.100.1.50`). Effective: `10.100.1.50` for dc1_fra nodes.
- **`log_level`**: common (`info`) → production (`warning`), staging (`debug`).
- **`client_timeout` / `server_timeout`**: common (`30s`) → production (`60s`).
- **`stats_enabled`**: common (`true`) → production (`false`) → node `lb01` (`true`). Effective: `true` only on `lb01.fra.example.com` in production.
- **`stats_port`**: common (`9000`) → node `lb01` (`9001`). Effective: `9001` on `lb01.fra.example.com`.
- **`backends`**: deep-merged across all levels — common (base structure) → dc1_fra (Frankfurt IPs) → haproxy_prod_fra (adds internal_monitoring) → lb01 (api weight asymmetry). Merge strategy: `deep` (Puppet `lookup_options`).

### Merge Strategy Notes

- `profile_haproxy::backends` uses `deep` merge — hash values are recursively merged across all Hiera levels; each level contributes additive or override keys without replacing the entire hash
- All other variables use `first` (default) — first value found in the hierarchy wins, no merging

## Custom Types and Providers

### Custom Fact: `haproxy_version`

- **File**: `site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb`
- **What it does**: Runs `haproxy -v 2>/dev/null` on Linux only (`confine kernel: 'Linux'`), extracts the semantic version string (e.g., `2.6.14`) using regex `/version\s+(\d+\.\d+\.\d+)/`, returns it as a string fact. Returns `nil` if HAProxy is not installed or output does not match.
- **Used in**: Potentially in templates or conditionals to gate version-specific config options.
- **Ansible equivalent**:
  ```yaml
  - name: Get HAProxy version
    ansible.builtin.command: haproxy -v
    register: haproxy_v_output
    ignore_errors: true
    changed_when: false
    when: ansible_system == 'Linux'

  - name: Set haproxy_version fact
    ansible.builtin.set_fact:
      haproxy_version: "{{ haproxy_v_output.stdout | regex_search('version\\s+(\\d+\\.\\d+\\.\\d+)', '\\1') | first }}"
    when: haproxy_v_output.rc == 0
  ```

## Dependencies

**External module dependencies** (from metadata.json / Puppetfile):
- `puppetlabs-stdlib` v9.7.0 — provides `empty()`, `normalize_port()` functions used in base_utils
- `puppetlabs-concat` v9.0.2 — used by `haproxy::balancermember` defined type for fragment-based config assembly
- `puppetlabs-firewall` v8.1.3 — provides `firewall` resource type (used in firewall.pp for iptables rules if applicable)

**System package dependencies**:
- `haproxy` — core load balancer package
- `hatop` (Debian only) — HAProxy terminal UI
- `haproxy-systemd-wrapper` (RedHat only) — systemd integration wrapper
- `policycoreutils-python-utils` (RedHat only) — SELinux policy management (`semanage`, `restorecon`)
- `ufw` (Debian only) — firewall management
- `chrony` — NTP client
- `rsyslog` — syslog daemon

**Service dependencies** (ordering):
- `profile::base::base` must complete before `profile::loadbalancer::haproxy` starts
- Within profile_haproxy: `install → config → discover ~> service`
- Config validation (`haproxy_config_check`) must pass before service is managed

## Puppet Facts Used

- `$facts['kernel']` — guards Linux-only resources in role and base profile; value: `Linux`
- `$facts['kernel'].downcase` — used in role conditional; value: `linux`
- `$facts['networking']['fqdn']` — used in `discover.pp` as exported balancermember title and server_name; e.g., `lb01.fra.example.com`
- `$facts['networking']['ip']` — used in `discover.pp` as exported balancermember IP address; e.g., `10.100.1.1`
- `$facts['puppet_environment']` — used in PuppetDB query to scope app server discovery to the same Puppet environment; e.g., `production`
- `fact('environment')` — used in `profile::loadbalancer::haproxy` to read the current environment string

## Template Conversion Notes

### `profile_haproxy/haproxy.cfg.erb` (19 variables, 3 logic blocks)

- **Logic block 1** — SSL frontend stanza: `<% if ssl_enabled %>` renders `bind *:443 ssl crt <%= ssl_cert_path %> key <%= ssl_key_path %> ciphers <%= ssl_ciphers %> ssl-min-ver <%= ssl_min_version %>`
- **Logic block 2** — Stats frontend stanza: `<% if stats_enabled %>` renders `listen stats`, `bind *:<%= stats_port %>`, `stats uri <%= stats_uri %>`, `stats auth <%= stats_user %>:<%= stats_password %>`
- **Logic block 3** — Stick-table stanza: `<% if stick_table_enabled %>` renders `stick-table type ip size <%= stick_table_size %> expire <%= stick_table_expire %> store conn_cur`
- ⚠️ **Variable count note**: The 19-variable count does not explicitly include `stick_table_size` and `stick_table_expire`, which are rendered inside logic block 3. Verify whether these are passed as separate template variables or accessed as attributes of a hash. If separate, the true count is 21. Note this discrepancy for the template conversion engineer.
- All 19 (or 21) variables are listed in the config.pp section above.

### `profile_haproxy/backend.conf.epp` (10 variables, 3 logic blocks)

- This is an **EPP** template — uses `<%= $variable %>` output syntax with explicit `|parameters|` declaration block and `$`-prefixed variable names (distinguishing it from ERB's unscoped variable access)
- **Logic block 1** — server iteration: `<% $servers.each |$s| { %>` renders one `server <%= $s['name'] %> <%= $s['address'] %>:<%= $port %> weight <%= $s['weight'] %> check` line per server
- **Logic block 2** — health check option: `<% if $health_check { %>` renders `option <%= $health_check %>` and `timeout check <%= $health_interval %>`
- **Logic block 3** — stick-table reference: `<% if $stick_table_enabled { %>` renders `stick on src table webservers` (only meaningful for webservers backend)
- Rendered once per backend — **3 times total** for `lb01.fra.example.com` in `haproxy_prod_fra`: `webservers`, `api`, `internal_monitoring`; **2 times** for nodes outside `haproxy_prod_fra`: `webservers`, `api`

## PuppetDB Dependencies

⚠️ **Critical migration blocker** — this module relies on PuppetDB for dynamic backend discovery. Ansible has no native equivalent. A replacement strategy is required before migration can be completed.

**Exported Resources** (`@@`):
- `@@haproxy::balancermember[$facts['networking']['fqdn']]` in `profile_haproxy::discover`
  - Each HAProxy node exports itself as a `webservers` balancermember with its own FQDN, IP, and port 8080
  - Collected by other HAProxy nodes to build the webservers backend dynamically
  - **Migration note**: Use dynamic inventory (e.g., AWS/GCP/VMware inventory plugin) or a service registry (Consul, etcd) to enumerate webserver nodes; populate `haproxy_backends.webservers.servers` from inventory groups

**Resource Collectors** (`<<| |>>`):
- `Haproxy::Balancermember <| listening_service == 'webservers' |>` in `profile_haproxy::discover`
  - Realizes all exported webserver balancermembers from PuppetDB
  - **Migration note**: Query inventory group `webservers` and generate backend server list via Jinja2 loop in template

**PuppetDB Queries** (`puppetdb_query()`):
- Query: `resources[certname, parameters] { type = 'Class' and title = 'Profile::App_server' and certname in resources[certname] { type = 'Class' and title = 'Profile::Base' and parameters.environment = '${facts['puppet_environment']}' } }`
  - Discovers all nodes classified with `Profile::App_server` in the same Puppet environment
  - Result stored in `$app_servers`, drives the loop that adds members to the `api` backend
  - ⚠️ **Note**: This query string is inferred from the manifest source; it is not represented as a distinct node in the execution tree and cannot be verified from the execution tree alone. If the query string is incorrect, the Ansible replacement strategy could target the wrong inventory group.
  - **Migration note**: Use an Ansible inventory group (e.g., `app_servers`) filtered by environment; iterate `groups['app_servers']` in the template or in a `set_fact` task to build `haproxy_backends.api.servers`

## Checks for the Migration

**Files to verify after migration**:
- `/etc/haproxy/haproxy.cfg` — main config
- `/etc/haproxy/conf.d/webservers.cfg` — webservers backend fragment
- `/etc/haproxy/conf.d/api.cfg` — api backend fragment
- `/etc/haproxy/conf.d/internal_monitoring.cfg` — internal_monitoring backend fragment (haproxy_prod_fra cluster only)
- `/etc/haproxy/conf.d/stick-tables.cfg` — stick-table config (production only)
- `/etc/haproxy/errors/503.http` — custom 503 error page
- `/etc/haproxy/errors/408.http` — custom 408 error page
- `/etc/logrotate.d/haproxy` — log rotation config
- `/etc/motd` — message of the day (base_utils)

**Service endpoints to check**:
- HTTP frontend: port `80`
- HTTPS frontend: port `443` (production / `ssl_enabled=true` only)
- HAProxy stats UI: `http://lb01.fra.example.com:9001/haproxy-stats` (lb01 node only)
- Internal monitoring backend: port `9090` (haproxy_prod_fra cluster only)

**Templates rendered**:
- `haproxy.cfg.erb` → `/etc/haproxy/haproxy.cfg` — rendered **1 time** per node
- `backend.conf.epp` → `/etc/haproxy/conf.d/webservers.cfg` — rendered **1 time** per node
- `backend.conf.epp` → `/etc/haproxy/conf.d/api.cfg` — rendered **1 time** per node
- `backend.conf.epp` → `/etc/haproxy/conf.d/internal_monitoring.cfg` — rendered **1 time** per node (haproxy_prod_fra only)

## Pre-flight checks:

```bash
# Validate HAProxy config syntax
haproxy -c -f /etc/haproxy/haproxy.cfg

# Verify HAProxy service state
systemctl status haproxy

# Verify installed HAProxy version (custom fact equivalent)
haproxy -v

# Verify webservers backend fragment exists and is non-empty
test -s /etc/haproxy/conf.d/webservers.cfg && echo "OK: webservers.cfg present"

# Verify api backend fragment exists and is non-empty
test -s /etc/haproxy/conf.d/api.cfg && echo "OK: api.cfg present"

# Verify internal_monitoring backend fragment (haproxy_prod_fra cluster only)
test -s /etc/haproxy/conf.d/internal_monitoring.cfg && echo "OK: internal_monitoring.cfg present"

# Verify stick-tables config (production only)
test -s /etc/haproxy/conf.d/stick-tables.cfg && echo "OK: stick-tables.cfg present"

# Verify custom error pages
test -f /etc/haproxy/errors/503.http && echo "OK: 503.http present"
test -f /etc/haproxy/errors/408.http && echo "OK: 408.http present"

# Verify log rotation config
test -f /etc/logrotate.d/haproxy && echo "OK: logrotate config present"

# Verify HAProxy stats page accessible on lb01 (run on lb01.fra.example.com only)
curl -u admin:[password] http://localhost:9001/haproxy-stats

# Verify HTTP frontend reachable
curl -o /dev/null -s -w "%{http_code}" http://localhost:80/

# Verify HTTPS frontend reachable (production only)
curl -o /dev/null -s -w "%{http_code}" https://localhost:443/

# Verify internal_monitoring backend reachable (haproxy_prod_fra cluster only)
curl -o /dev/null -s -w "%{http_code}" http://localhost:9090/-/healthy

# RedHat only: verify SELinux boolean is set
getsebool haproxy_connect_any

# RedHat only: verify firewalld rules
firewall-cmd --list-all --zone=public

# Debian only: verify ufw rules
ufw status
```