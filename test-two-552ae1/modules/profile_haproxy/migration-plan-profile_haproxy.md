---
source-path: site/modules/linux/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module deploys and manages HAProxy as a load balancer on Linux systems. It installs the HAProxy package and OS-specific dependencies, creates the system user/group, writes a main `haproxy.cfg` from an ERB template, generates per-backend config fragments from an EPP template via a Hiera-driven loop, manages error pages, optionally configures stick tables, validates config before service restarts, configures logrotate, and opens firewall ports via either `firewalld` (RedHat) or `ufw` (Debian). A `discover` class uses PuppetDB exported resources and live queries to dynamically register backend members — this is the most complex migration challenge. The full Hiera hierarchy spans 7 levels (common → OS → environment → datacenter → cluster → node), with the `backends` hash deep-merged across all levels.

---

## Service Type and Instances

**Service Type**: Load Balancer (HAProxy)

**Configured Instances** (fully resolved for `lb01.fra.example.com` in `haproxy_prod_fra` cluster, `dc1_fra` datacenter, `production` environment):

- **haproxy** (main service):
  - Config file: `/etc/haproxy/haproxy.cfg`
  - Config dir: `/etc/haproxy`
  - Listens: port `80` (HTTP), port `443` (HTTPS, SSL-terminated), port `9001` (stats, node-level override)
  - Stats URI: `/haproxy-stats`, user: `admin`, password: eyaml-encrypted
  - Global maxconn: `32768` (cluster-level override wins over production `16384` and common `4096`)
  - SSL: enabled (production), ciphers: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`, min version: `TLSv1.3`
  - Log server: `10.100.1.50` (datacenter override), facility: `local0`, level: `warning` (production override)

- **webservers** backend (deep-merged: common base + dc1_fra server addresses):
  - Balance: `roundrobin`, port: `8080`, health: `httpchk GET /health` every `5s`
  - Servers: `web1-fra:10.100.1.10:8080 weight 100`, `web2-fra:10.100.1.11:8080 weight 100`, `web3-fra:10.100.1.12:8080 weight 100`

- **api** backend (deep-merged: common base + dc1_fra addresses + lb01 weight overrides):
  - Balance: `leastconn`, port: `3000`, health: `httpchk GET /api/health` every `10s`
  - Servers: `api1-fra:10.100.2.10:3000 weight 200`, `api2-fra:10.100.2.11:3000 weight 100`

- **internal_monitoring** backend (cluster-level addition only):
  - Balance: `roundrobin`, port: `9090`, health: `httpchk GET /-/healthy` every `15s`
  - Servers: `prom1-fra:10.100.3.10:9090 weight 100`

- **stick-tables** (production only):
  - File: `/etc/haproxy/conf.d/stick-tables.cfg`
  - Size: `200k`, expire: `30m`

---

## File Structure

```
site/role/manifests/haproxy.pp
site/profile/manifests/base/base.pp
site/profile/manifests/loadbalancer/haproxy.pp
site/modules/linux/profile_haproxy/manifests/init.pp
site/modules/linux/profile_haproxy/manifests/install.pp
site/modules/linux/profile_haproxy/manifests/config.pp
site/modules/linux/profile_haproxy/manifests/discover.pp
site/modules/linux/profile_haproxy/manifests/service.pp
site/modules/linux/profile_haproxy/manifests/firewall.pp
site/modules/common/base_utils/manifests/init.pp
site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb
site/modules/linux/profile_haproxy/templates/backend.conf.epp
site/modules/linux/profile_haproxy/data/common.yaml
site/modules/linux/profile_haproxy/data/os/RedHat.yaml
site/modules/linux/profile_haproxy/data/os/Debian.yaml
site/modules/linux/profile_haproxy/data/environment/production.yaml
site/modules/linux/profile_haproxy/data/environment/staging.yaml
site/modules/linux/profile_haproxy/data/datacenter/dc1_fra.yaml
site/modules/linux/profile_haproxy/data/cluster/haproxy_prod_fra.yaml
site/modules/linux/profile_haproxy/data/nodes/lb01.fra.example.com.yaml
site/modules/common/base_utils/data/os/Debian.yaml
site/modules/common/base_utils/data/os/RedHat.yaml
site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb
modules/profile_haproxy/haproxy_errors/503.http  (Puppet fileserver static source)
modules/profile_haproxy/haproxy_errors/408.http  (Puppet fileserver static source)
```

---

## Module Explanation

The module performs operations in this order:

### 1. **role::haproxy** (`site/role/manifests/haproxy.pp`)
- Conditional: `if $facts['kernel'].downcase == 'linux'` → Linux-only guard
- `include ::profile::base::base`
- `include ::profile::loadbalancer::haproxy`
- Ordering: `Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']`
- Uses fact: `$facts['kernel']`

### 2. **::profile::base::base** (`site/profile/manifests/base/base.pp`)
- Conditional: `if $manage_utils` → `include base_utils`

  #### 2a. **base_utils** (`site/modules/common/base_utils/manifests/init.pp`)
  - Conditional: `if $manage_motd` (default: `true`) → `file '/etc/motd'` → owner: `root`, group: `root`, mode: `0644`, content: rendered from template `base_utils/motd.erb`
  - **Loop** `$utility_packages.each` — runs **5 times** on Debian, **5 times** on RedHat:
    - **Debian** — packages: `vim`, `wget`, `curl`, `jq`, `dnsutils`:
      - `package 'vim'` → ensure: `installed`
      - `package 'wget'` → ensure: `installed`
      - `package 'curl'` → ensure: `installed`
      - `package 'jq'` → ensure: `installed`
      - `package 'dnsutils'` → ensure: `installed`
    - **RedHat** — packages: `vim-enhanced`, `wget`, `curl`, `jq`, `bind-utils`:
      - `package 'vim-enhanced'` → ensure: `installed`
      - `package 'wget'` → ensure: `installed`
      - `package 'curl'` → ensure: `installed`
      - `package 'jq'` → ensure: `installed`
      - `package 'bind-utils'` → ensure: `installed`
  - Conditional: `if $manage_ntp and $facts['kernel'] == 'Linux'`:
    - `package 'chrony'` → ensure: `present`
    - `service 'chronyd'` → ensure: `running`, enable: `true`
  - Conditional: `if $manage_syslog and $facts['kernel'] == 'Linux'`:
    - `package 'rsyslog'` → ensure: `present`
    - `service 'rsyslog'` → ensure: `running`, enable: `true`

### 3. **::profile::loadbalancer::haproxy** (`site/profile/manifests/loadbalancer/haproxy.pp`)
- Thin wrapper; reads `fact('environment')` as `$environment_name`
- Instantiates `class { 'profile_haproxy': }` — all parameters resolved from Hiera

### 4. **profile_haproxy** (`site/modules/linux/profile_haproxy/manifests/init.pp`)
- Resolves all class parameters from Hiera (see Variables section for fully resolved values)
- `contain profile_haproxy::install`
- `contain profile_haproxy::config`
- `contain profile_haproxy::discover`
- `contain profile_haproxy::service`
- `contain profile_haproxy::firewall`
- Ordering chain:
  - `Class['profile_haproxy::install'] -> Class['profile_haproxy::config']`
  - `Class['profile_haproxy::config'] -> Class['profile_haproxy::discover']`
  - `Class['profile_haproxy::discover'] ~> Class['profile_haproxy::service']` (notify: discover changes trigger service restart)

### 5. **profile_haproxy::install** (`site/modules/linux/profile_haproxy/manifests/install.pp`)
- `package 'haproxy'` → ensure: `installed`
- Conditional: `if !empty($extra_packages)` — **RedHat** (selinux_enabled: `true`, extra_packages: `[haproxy-systemd-wrapper, policycoreutils-python-utils]`):
  - `package 'haproxy-systemd-wrapper'` → ensure: `installed`, require: `Package[haproxy]`
  - `package 'policycoreutils-python-utils'` → ensure: `installed`, require: `Package[haproxy]`
- Conditional: **Debian** (extra_packages: `[hatop]`):
  - `package 'hatop'` → ensure: `installed`, require: `Package[haproxy]`
- `group 'haproxy'` → ensure: `present`, system: `true`
- `user 'haproxy'` → ensure: `present`, gid: `haproxy`, home: `/var/lib/haproxy`, shell: `/sbin/nologin`, system: `true`, require: `Group[haproxy]`
- `file ['/etc/haproxy', '/etc/haproxy/conf.d']` → ensure: `directory`, owner: `root`, group: `haproxy`, mode: `0755`
- `file '/var/lib/haproxy'` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0750`
- Conditional: `if $selinux_enabled` — **RedHat only** (selinux_enabled: `true`):
  - `exec 'haproxy_selinux_connect'` → command: `setsebool -P haproxy_connect_any 1`, unless: `getsebool haproxy_connect_any | grep -q on`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, require: `Package[haproxy]`
- **Debian** (selinux_enabled: `false`): SELinux exec is skipped entirely

### 6. **profile_haproxy::config** (`site/modules/linux/profile_haproxy/manifests/config.pp`)

- `file '/etc/haproxy/haproxy.cfg'` (template `profile_haproxy/haproxy.cfg.erb`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, notify: `Class['profile_haproxy::service']`
  - Template variables passed (19 variables, 5 logic blocks):
    - `@log_server` = `10.100.1.50` (dc1_fra override)
    - `@log_facility` = `local0`
    - `@log_level` = `warning` (production override)
    - `@global_maxconn` = `32768` (cluster override)
    - `@user` = `haproxy`
    - `@group` = `haproxy`
    - `@ssl_enabled` = `true` (production override)
    - `@ssl_ciphers` = `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (cluster override)
    - `@connect_timeout` = `5s`
    - `@client_timeout` = `60s` (production override)
    - `@server_timeout` = `60s` (production override)
    - `@retries` = `3`
    - `@stats_enabled` = `true` (node-level override re-enables despite production suppression)
    - `@stats_port` = `9001` (node-level override)
    - `@stats_uri` = `/haproxy-stats`
    - `@stats_user` = `admin`
    - `@stats_password` = `<eyaml-decrypted value>` (Sensitive[String], redacted in logs)
    - `@ssl_cert_path` = `/etc/ssl/certs`
    - `@backends` = deep-merged hash (used only for comment loop in template; actual backend config is in conf.d/)
  - Logic blocks:
    - `<% if @ssl_enabled -%>` in global section → renders `ssl-default-bind-ciphers`, `ssl-default-bind-options`, `tune.ssl.default-dh-param 2048`
    - `<% if @stats_enabled -%>` → renders entire `listen stats` block with bind `*:9001`, uri `/haproxy-stats`, auth `admin:<password>`
    - `<% if @ssl_enabled -%>` in frontend section → renders `bind *:443 ssl crt /etc/ssl/certs/haproxy.pem` and redirect rule
    - `<% @backends.each do |name, config| -%>` → renders comment-only lines (no functional config)

- **Loop** `$profile_haproxy::backends.each` — runs **3 times** for fully-resolved deep-merged backends: **webservers**, **api**, **internal_monitoring**

  - **webservers**:
    - `file '/etc/haproxy/conf.d/webservers.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, notify: `Class['profile_haproxy::service']`
    - EPP variables:
      - `$backend_name` = `webservers`
      - `$balance` = `roundrobin`
      - `$port` = `8080`
      - `$servers` = `[{name: web1-fra, address: 10.100.1.10, weight: 100}, {name: web2-fra, address: 10.100.1.11, weight: 100}, {name: web3-fra, address: 10.100.1.12, weight: 100}]`
      - `$health_check` = `httpchk GET /health`
      - `$health_interval` = `5s`
      - `$ssl_enabled` = `true`
    - Renders: `server web1-fra 10.100.1.10:8080 check weight 100 ssl verify none`, `server web2-fra 10.100.1.11:8080 check weight 100 ssl verify none`, `server web3-fra 10.100.1.12:8080 check weight 100 ssl verify none`

  - **api**:
    - `file '/etc/haproxy/conf.d/api.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, notify: `Class['profile_haproxy::service']`
    - EPP variables:
      - `$backend_name` = `api`
      - `$balance` = `leastconn`
      - `$port` = `3000`
      - `$servers` = `[{name: api1-fra, address: 10.100.2.10, weight: 200}, {name: api2-fra, address: 10.100.2.11, weight: 100}]` (node-level weight override applied)
      - `$health_check` = `httpchk GET /api/health`
      - `$health_interval` = `10s`
      - `$ssl_enabled` = `true`
    - Renders: `server api1-fra 10.100.2.10:3000 check weight 200 ssl verify none`, `server api2-fra 10.100.2.11:3000 check weight 100 ssl verify none`

  - **internal_monitoring** (cluster-level addition):
    - `file '/etc/haproxy/conf.d/internal_monitoring.cfg'` (template `profile_haproxy/backend.conf.epp`) → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, notify: `Class['profile_haproxy::service']`
    - EPP variables:
      - `$backend_name` = `internal_monitoring`
      - `$balance` = `roundrobin`
      - `$port` = `9090`
      - `$servers` = `[{name: prom1-fra, address: 10.100.3.10, weight: 100}]`
      - `$health_check` = `httpchk GET /-/healthy`
      - `$health_interval` = `15s`
      - `$ssl_enabled` = `true`
    - Renders: `server prom1-fra 10.100.3.10:9090 check weight 100 ssl verify none`

- **Loop** `['503', '408'].each` — runs **2 times**:
  - `file '/etc/haproxy/errors/503.http'` → ensure: `file`, source: `puppet:///modules/profile_haproxy/haproxy_errors/503.http`, owner: `root`, group: `haproxy`, mode: `0644`
  - `file '/etc/haproxy/errors/408.http'` → ensure: `file`, source: `puppet:///modules/profile_haproxy/haproxy_errors/408.http`, owner: `root`, group: `haproxy`, mode: `0644`

- `file '/etc/haproxy/errors'` → ensure: `directory`, owner: `root`, group: `haproxy`, mode: `0755`, before: `File[/etc/haproxy/errors/503.http]`

- Conditional: `if $stick_table_enabled` — **production** (stick_table_enabled: `true`):
  - `file '/etc/haproxy/conf.d/stick-tables.cfg'` → ensure: `file`, owner: `root`, group: `haproxy`, mode: `0640`, notify: `Class['profile_haproxy::service']`
  - Content: `# Managed by Puppet\nstick-table type ip size 200k expire 30m\n`
- **staging** (stick_table_enabled: `false`): stick-tables file is skipped

### 7. **profile_haproxy::discover** (`site/modules/linux/profile_haproxy/manifests/discover.pp`)

> ⚠️ **PuppetDB-dependent class** — this entire class relies on PuppetDB infrastructure with no direct Ansible equivalent. See PuppetDB Dependencies section.

- **Exported resource** `@@haproxy::balancermember[$facts['networking']['fqdn']]`:
  - listening_service: `webservers`
  - server_names: `<node FQDN from fact>`
  - ipaddresses: `<node IP from fact>`
  - ports: `8080`
  - options: `check`
  - This resource is exported to PuppetDB so other nodes can collect it

- **Resource collector** `Haproxy::Balancermember <<| listening_service == 'webservers' |>>`:
  - Collects all exported `haproxy::balancermember` resources tagged with `listening_service == 'webservers'` from PuppetDB
  - Realizes them on the HAProxy node

- **PuppetDB query** `puppetdb_query(...)` → assigns result to `$app_servers`:
  - Query: finds all nodes with class `Profile::App_server` that also have class `Profile::Base` with `parameters.environment` matching the current Puppet environment
  - Returns array of `{certname, parameters}` hashes

- **Loop** `$app_servers.each` — runs **N times** (N = number of app servers discovered in PuppetDB at catalog compile time; value is dynamic):
  - For each `$server` in results:
    - `haproxy::balancermember "api-${certname}"`:
      - listening_service: `api`
      - server_names: `<certname>`
      - ipaddresses: `<certname>` (DNS-resolved)
      - ports: `<$server['parameters']['port']>` (from app server's Puppet class parameter)
      - options: `check inter 10s`

- Uses facts: `$facts['networking']['fqdn']`, `$facts['networking']['ip']`, `$facts['puppet_environment']`

### 8. **profile_haproxy::service** (`site/modules/linux/profile_haproxy/manifests/service.pp`)

- `service 'haproxy'` → ensure: `running`, enable: `true`, hasrestart: `true`, hasstatus: `true`, require: `Package[haproxy]`, subscribe: `File[/etc/haproxy/haproxy.cfg]`
- `exec 'haproxy_config_check'` → command: `haproxy -c -f /etc/haproxy/haproxy.cfg`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, refreshonly: `true`, subscribe: `File[/etc/haproxy/haproxy.cfg]`, before: `Service[haproxy]`
- `file '/etc/logrotate.d/haproxy'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`
  - Content: inline heredoc — daily rotation, 14 rotations, compress, delaycompress, postrotate sends HUP to haproxy PID
- **Notification chain**:
  - `File[/etc/haproxy/haproxy.cfg] ~> Exec['haproxy_config_check']` (config change triggers validation)
  - `Exec['haproxy_config_check'] -> Service['haproxy']` (validation must pass before service action)
  - `File[/etc/haproxy/haproxy.cfg] ~> Service['haproxy']` (config change also directly notifies service)

### 9. **profile_haproxy::firewall** (`site/modules/linux/profile_haproxy/manifests/firewall.pp`)

- Looks up `$firewall_provider` from Hiera (RedHat: `firewalld`, Debian: `ufw`)

- **Case `firewalld`** (RedHat systems):
  - Looks up `$firewall_zone` = `public`
  - **Loop** `['80', '443'].each` — runs **2 times**:
    - `exec 'firewalld_allow_80'` → command: `firewall-cmd --zone=public --add-port=80/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=80/tcp`, path: `[/usr/bin, /bin]`, notify: `Exec['firewalld_reload']`
    - `exec 'firewalld_allow_443'` → command: `firewall-cmd --zone=public --add-port=443/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=443/tcp`, path: `[/usr/bin, /bin]`, notify: `Exec['firewalld_reload']`
  - Conditional: `if $stats_enabled` (true on lb01):
    - `exec 'firewalld_allow_stats_9001'` → command: `firewall-cmd --zone=public --add-port=9001/tcp --permanent`, unless: `firewall-cmd --zone=public --query-port=9001/tcp`, path: `[/usr/bin, /bin]`, notify: `Exec['firewalld_reload']`
  - `exec 'firewalld_reload'` → command: `firewall-cmd --reload`, path: `[/usr/bin, /bin]`, refreshonly: `true`

- **Case `ufw`** (Debian systems):
  - `package 'ufw'` → ensure: `installed`
  - `exec 'ufw_allow_http'` → command: `ufw allow 80/tcp`, unless: `ufw status | grep -q "80/tcp.*ALLOW"`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, require: `Package[ufw]`
  - `exec 'ufw_allow_https'` → command: `ufw allow 443/tcp`, unless: `ufw status | grep -q "443/tcp.*ALLOW"`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, require: `Package[ufw]`
  - Conditional: `if $stats_enabled` (true on lb01) — **verify in manifest**: `exec 'ufw_allow_stats'` → command: `ufw allow 9001/tcp`, unless: `ufw status | grep -q "9001/tcp.*ALLOW"`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, require: `Package[ufw]`
  - `exec 'ufw_enable'` → command: `ufw --force enable`, unless: `ufw status | grep -q "Status: active"`, path: `[/usr/sbin, /usr/bin, /sbin, /bin]`, require: `Package[ufw]`

- **Case `default`** (unknown provider):
  - `notify 'Unknown firewall provider: <provider>'` → emits Puppet log message only

---

## Variables

**Variable Flow Summary**: 35+ variables across 7 Hiera levels (common → OS → environment → datacenter → cluster → node → control-repo). The `backends` hash is the only deep-merged key; all others use first-match wins.

### Variable Definitions

**common.yaml (module defaults — lowest priority)** → Migration note: Base defaults for all nodes; map to `roles/haproxy/defaults/main.yml`
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
- `profile_haproxy::stats_password`: `ENC[PKCS7,MIIBygYJKoZIhvcNAQcDoIIBuzCCAbcCAQAxggEhMIIBHQIBADAFMAACAQEwDQYJKoZIhvcNAQEBBQAEggEAExample]` (type: string, eyaml-encrypted, Sensitive[String] at runtime)
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
- `profile_haproxy::backends`: `{webservers: {balance: roundrobin, port: 8080, ...}, api: {balance: leastconn, port: 3000, ...}}` (type: hash, deep-merge)
- `base_utils::manage_motd`: `true` (type: boolean)
- `base_utils::motd_template`: `base_utils/motd.erb` (type: string)
- `base_utils::utility_packages`: `[]` (type: array, overridden at OS level)

**os/RedHat.yaml** → Migration note: OS-specific variables, loaded conditionally based on OS family; map to `group_vars/RedHat.yml`
- `profile_haproxy::firewall_provider`: `firewalld` (type: string)
- `profile_haproxy::firewall_zone`: `public` (type: string)
- `profile_haproxy::extra_packages`: `[haproxy-systemd-wrapper, policycoreutils-python-utils]` (type: array)
- `profile_haproxy::selinux_enabled`: `true` (type: boolean)

**os/Debian.yaml** → Migration note: OS-specific variables, loaded conditionally based on OS family; map to `group_vars/Debian.yml`
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::extra_packages`: `[hatop]` (type: array)
- `profile_haproxy::selinux_enabled`: `false` (type: boolean)

**site/modules/common/base_utils/data/os/Debian.yaml** → Migration note: Belongs to base_utils module; map to `group_vars/Debian.yml`
- `base_utils::utility_packages`: `[vim, wget, curl, jq, dnsutils]` (type: array)

**site/modules/common/base_utils/data/os/RedHat.yaml** → Migration note: Belongs to base_utils module; map to `group_vars/RedHat.yml`
- `base_utils::utility_packages`: `[vim-enhanced, wget, curl, jq, bind-utils]` (type: array)

**environment/production.yaml** → Migration note: Production environment overrides; map to `group_vars/production.yml`
- `profile_haproxy::global_maxconn`: `16384` (type: integer, overrides common `4096`; itself overridden by cluster to `32768`)
- `profile_haproxy::ssl_enabled`: `true` (type: boolean, overrides common `false`)
- `profile_haproxy::log_level`: `warning` (type: string, overrides common `info`)
- `profile_haproxy::client_timeout`: `60s` (type: string, overrides common `30s`)
- `profile_haproxy::server_timeout`: `60s` (type: string, overrides common `30s`)
- `profile_haproxy::stats_enabled`: `false` (type: boolean, overrides common `true`; re-enabled at node level for lb01)
- `profile_haproxy::stick_table_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_size`: `200k` (type: string)
- `profile_haproxy::stick_table_expire`: `30m` (type: string)

**environment/staging.yaml** → Migration note: Staging environment overrides; map to `group_vars/staging.yml`
- `profile_haproxy::global_maxconn`: `2048` (type: integer, overrides common `4096`)
- `profile_haproxy::ssl_enabled`: `false` (type: boolean, explicit)
- `profile_haproxy::log_level`: `debug` (type: string, overrides common `info`)
- `profile_haproxy::stats_enabled`: `true` (type: boolean, explicit)
- `profile_haproxy::stick_table_enabled`: `false` (type: boolean)

**datacenter/dc1_fra.yaml** → Migration note: Datacenter-specific overrides; map to `group_vars/dc1_fra.yml`
- `profile_haproxy::log_server`: `10.100.1.50` (type: string, overrides common `127.0.0.1`)
- `profile_haproxy::ntp_servers`: `[ntp1.dc1.fra.example.com, ntp2.dc1.fra.example.com]` (type: array)
- `profile_haproxy::backends` (deep-merge contribution):
  - `webservers.servers`: replaces with `[web1-fra:10.100.1.10, web2-fra:10.100.1.11, web3-fra:10.100.1.12]`
  - `api.servers`: replaces with `[api1-fra:10.100.2.10, api2-fra:10.100.2.11]`

**cluster/haproxy_prod_fra.yaml** → Migration note: Cluster-specific overrides; map to `group_vars/haproxy_prod_fra.yml`
- `profile_haproxy::global_maxconn`: `32768` (type: integer, final winning value for this cluster)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (type: string, overrides common AES128 suite)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (type: string, overrides common `TLSv1.2`)
- `profile_haproxy::backends` (deep-merge contribution):
  - `internal_monitoring`: `{balance: roundrobin, port: 9090, health_check: httpchk GET /-/healthy, health_interval: 15s, servers: [{name: prom1-fra, address: 10.100.3.10, weight: 100}]}`

**nodes/lb01.fra.example.com.yaml (highest priority)** → Migration note: Host-specific overrides; map to `host_vars/lb01.fra.example.com.yml`
- `profile_haproxy::stats_enabled`: `true` (type: boolean, re-enables despite production suppression)
- `profile_haproxy::stats_port`: `9001` (type: integer, overrides common `9000`)
- `profile_haproxy::backends` (deep-merge contribution):
  - `api.servers`: overrides with `[{api1-fra: 10.100.2.10, weight: 200}, {api2-fra: 10.100.2.11, weight: 100}]`

### Variable Migration Summary

- **Common defaults**: 28 variables from common.yaml → `roles/haproxy/defaults/main.yml` (base configuration for all nodes)
- **OS-specific variables**: 4 variables per OS family → `group_vars/RedHat.yml`, `group_vars/Debian.yml`
- **Environment-specific variables**: 9 variables (production), 5 variables (staging) → `group_vars/production.yml`, `group_vars/staging.yml`
- **Datacenter-specific variables**: 3 variables → `group_vars/dc1_fra.yml`
- **Cluster-specific variables**: 4 variables → `group_vars/haproxy_prod_fra.yml`
- **Host-specific variables**: 3 variables → `host_vars/lb01.fra.example.com.yml`
- **Encrypted variables**: 1 variable (`stats_password`) needing ansible-vault re-encryption

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **`profile_haproxy::global_maxconn`**: defined at common (`4096`), production (`16384`), staging (`2048`), cluster/haproxy_prod_fra (`32768`); merge strategy: first-match; final value for lb01: `32768`
- **`profile_haproxy::ssl_enabled`**: defined at common (`false`), production (`true`), staging (`false`); merge strategy: first-match; final value for production: `true`
- **`profile_haproxy::ssl_ciphers`**: defined at common (AES128 suite), cluster/haproxy_prod_fra (AES256 suite); merge strategy: first-match; final value for haproxy_prod_fra: AES256 suite
- **`profile_haproxy::ssl_min_version`**: defined at common (`TLSv1.2`), cluster/haproxy_prod_fra (`TLSv1.3`); merge strategy: first-match; final value for haproxy_prod_fra: `TLSv1.3`
- **`profile_haproxy::log_level`**: defined at common (`info`), production (`warning`), staging (`debug`); merge strategy: first-match
- **`profile_haproxy::log_server`**: defined at common (`127.0.0.1`), datacenter/dc1_fra (`10.100.1.50`); merge strategy: first-match
- **`profile_haproxy::stats_enabled`**: defined at common (`true`), production (`false`), staging (`true`), node/lb01 (`true`); merge strategy: first-match; final value for lb01 in production: `true`
- **`profile_haproxy::stats_port`**: defined at common (`9000`), node/lb01 (`9001`); merge strategy: first-match; final value for lb01: `9001`
- **`profile_haproxy::client_timeout`**: defined at common (`30s`), production (`60s`); merge strategy: first-match
- **`profile_haproxy::server_timeout`**: defined at common (`30s`), production (`60s`); merge strategy: first-match
- **`profile_haproxy::backends`**: defined at common, dc1_fra, haproxy_prod_fra, lb01; merge strategy: **deep** (all levels contribute, with higher-priority levels overwriting specific sub-keys)

### Merge Strategy Notes

- Variables using `deep` merge — `profile_haproxy::backends`: hash values are recursively merged across all Hiera levels; higher-priority levels overwrite specific sub-keys while lower-priority keys are preserved
- Variables using `first` (default) — all other variables: first value found in the hierarchy wins, no merging

---

## Custom Types and Providers

**Custom Fact: `haproxy_version`** (`site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb`)
- Runs `haproxy -v 2>/dev/null` on the target node
- Parses output with regex `/version\s+(\d+\.\d+\.\d+)/`
- Returns semantic version string (e.g., `2.6.14`) or `nil` if not installed/parseable
- Confined to Linux kernel only (`confine :kernel => 'Linux'`)
- **Ansible equivalent**: Use `ansible.builtin.command: haproxy -v` with `register`, then `set_fact` using `regex_search('version\s+(\d+\.\d+\.\d+)', '\1') | first | default(omit)`. Guard with `when: ansible_system == 'Linux'`.

> ⚠️ **Unverified**: The structured analysis does not include a `base_utils::normalize_port` function file (`site/modules/common/base_utils/functions/normalize_port.pp`). The firewall class description references a call to this function to coerce `$stats_port` to Integer. Verify whether this file exists before migrating. If confirmed, the **Ansible equivalent** is the Jinja2 `| int` filter: `{{ haproxy_stats_port | int }}`.

---

## Dependencies

**External module dependencies**:
- `puppetlabs-stdlib` (9.7.0) — provides utility functions (`lookup`, `empty()`, `dig()`)
- `puppetlabs-concat` (9.0.2) — used by `haproxy::balancermember` defined type for fragment assembly
- `puppetlabs-firewall` (8.1.3) — provides `firewall` resource type (referenced indirectly; direct firewall management in this module uses `exec` with `firewall-cmd`/`ufw` instead)

**System package dependencies**:
- `haproxy` (all systems)
- `haproxy-systemd-wrapper` (RedHat only)
- `policycoreutils-python-utils` (RedHat only, for `setsebool`)
- `hatop` (Debian only, HAProxy terminal UI)
- `ufw` (Debian only, firewall)
- `chrony` (all, via base profile)
- `rsyslog` (all, via base profile)

**Service dependencies** (ordering):
- `profile_haproxy::install` must complete before `profile_haproxy::config`
- `profile_haproxy::config` must complete before `profile_haproxy::discover`
- `profile_haproxy::discover` notifies `profile_haproxy::service` (changes trigger restart)
- `profile::base::base` must complete before `profile::loadbalancer::haproxy`
- Config file change → config validation exec → service restart (three-step chain)

---

## Puppet Facts Used

- `$facts['kernel']` — guards Linux-only resources in `site/role/manifests/haproxy.pp` and `site/profile/manifests/base/base.pp`; value: `Linux`
- `$facts['networking']['fqdn']` — used in `site/modules/linux/profile_haproxy/manifests/discover.pp` as the exported balancermember title and `server_names` value; e.g., `lb01.fra.example.com`
- `$facts['networking']['ip']` — used in `site/modules/linux/profile_haproxy/manifests/discover.pp` as the exported balancermember `ipaddresses` value; e.g., `10.100.1.5`
- `$facts['puppet_environment']` — used in `site/modules/linux/profile_haproxy/manifests/discover.pp` PuppetDB query to scope app server discovery to the current Puppet environment; e.g., `production`
- `fact('environment')` — used in `site/profile/manifests/loadbalancer/haproxy.pp` as `$environment_name` parameter; same as `$facts['puppet_environment']`
- `haproxy_version` (custom fact, `site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb`) — returns installed HAProxy semantic version string; used for conditional logic or reporting; e.g., `2.6.14`

---

## Template Conversion Notes

### `site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb` → `haproxy.cfg.j2`

**Variables used** (19):
- `@log_server`, `@log_facility`, `@log_level` → global log line
- `@global_maxconn` → `maxconn` directive
- `@user`, `@group` → process identity
- `@ssl_enabled` → conditional block guard (appears twice: global section and frontend section)
- `@ssl_ciphers` → `ssl-default-bind-ciphers` (inside ssl block)
- `@connect_timeout`, `@client_timeout`, `@server_timeout` → timeout directives
- `@retries` → `retries` directive
- `@stats_enabled` → conditional stats block guard
- `@stats_port`, `@stats_uri`, `@stats_user`, `@stats_password` → stats listener config
- `@ssl_cert_path` → SSL certificate path in frontend bind
- `@backends` → iterated for comment lines only (actual config in conf.d/)

**Logic blocks** (5):
- `<% if @ssl_enabled -%>` in global section → renders `ssl-default-bind-ciphers`, `ssl-default-bind-options`, `tune.ssl.default-dh-param 2048`
- `<% if @stats_enabled -%>` → renders entire `listen stats` block with bind `*:9001`, uri `/haproxy-stats`, auth `admin:<password>`
- `<% if @ssl_enabled -%>` in frontend section → renders `bind *:443 ssl crt /etc/ssl/certs/haproxy.pem` and redirect rule
- `<% @backends.each do |name, config| -%>` → renders comment-only lines (no functional config)

**Ansible Jinja2 notes**:
- Replace `<% if @ssl_enabled -%>` with `{% if haproxy_ssl_enabled %}`
- Replace `<% @backends.each do |name, config| -%>` with `{% for name, config in haproxy_backends.items() %}`
- `@stats_password` must be referenced as `{{ haproxy_stats_password }}` with the value stored in ansible-vault
- The `haproxy.pem` path is constructed as `{{ haproxy_ssl_cert_path }}/haproxy.pem` — ensure the PEM bundle is pre-deployed

### `site/modules/linux/profile_haproxy/templates/backend.conf.epp` → `backend.conf.j2`

**Variables used** (structured analysis counts 10; 7 confirmed, 3 unidentified — verify in manifest):
- `$backend_name` → backend stanza name
- `$balance` → balance algorithm
- `$port` → server port (appended to each server address)
- `$servers` → array of `{name, address, weight}` hashes
- `$health_check` → optional `option` line
- `$health_interval` → optional `default-server inter` line
- `$ssl_enabled` → conditional `ssl verify none` suffix on server lines
- 3 additional variables counted by structured analysis (candidates: `$options`, `$timeout_connect`, `$timeout_server`) — verify in manifest

**Logic blocks** (3):
- `if $health_check` → renders `option <health_check>` line
- `if $health_interval` → renders `default-server inter <interval>` line
- `$servers.each` → renders one `server` line per entry; inline `if $ssl_enabled` appends `ssl verify none`

**Ansible Jinja2 notes**:
- This template is rendered once per backend (3 times for lb01 in haproxy_prod_fra: webservers, api, internal_monitoring)
- In Ansible, either use a single template with a `{% for backend_name, backend_config in haproxy_backends.items() %}` loop generating all conf.d files, or use `ansible.builtin.template` in a loop task
- The `$servers` array iteration maps directly to `{% for server in backend_config.servers %}`
- Optional parameters (`health_check`, `health_interval`) map to `{% if backend_config.health_check is defined %}`

---

## PuppetDB Dependencies

> ⚠️ **Critical migration challenge**: `site/modules/linux/profile_haproxy/manifests/discover.pp` relies entirely on PuppetDB infrastructure. There is no direct Ansible equivalent. The following patterns must be re-architected.

**Exported Resource** (`@@`):
- `@@haproxy::balancermember[$facts['networking']['fqdn']]` — each node running this class exports itself as a webservers backend member (IP: `$facts['networking']['ip']`, port: `8080`, options: `check`) to PuppetDB
- Migration note: This self-registration pattern has no Ansible equivalent. App servers must instead write their own entry to a shared registry (Consul, etcd, Netbox, or a flat inventory file) that the HAProxy playbook reads at runtime.

**Resource Collector** (`<<| |>>`):
- `Haproxy::Balancermember <<| listening_service == 'webservers' |>>` — the HAProxy node collects all exported balancermember resources tagged `webservers` from PuppetDB and realizes them locally
- Migration note: Replace with a pre-task that reads the shared registry populated by app servers and constructs the `haproxy_backends.webservers.servers` list dynamically before the HAProxy template is rendered.

**PuppetDB Query**:
- Query: `resources[certname, parameters] { type = 'Class' and title = 'Profile::App_server' and certname in resources[certname] { type = 'Class' and title = 'Profile::Base' and parameters.environment = '<current_env>' } }`
- Purpose: discovers all nodes with `Profile::App_server` class in the same Puppet environment
- Result: used to dynamically build `haproxy::balancermember` resources for the `api` backend
- Migration note: Replace with a dynamic inventory query against a CMDB or service registry scoped to the target environment. Use `ansible.builtin.add_host` or inventory groups to build the backend server list at playbook runtime.

**Ansible migration strategies for discover class**:
- **Option 1 (Static inventory)**: Pre-populate `haproxy_backends.api.servers` and `haproxy_backends.webservers.servers` in group_vars/host_vars. This is already partially done via the Hiera `backends` hash — the discover class supplements it dynamically.
- **Option 2 (Dynamic inventory)**: Use an Ansible dynamic inventory plugin (e.g., AWS EC2, Consul, Netbox) to discover app servers. Then use `ansible.builtin.add_host` or inventory groups to build the backend server list at playbook runtime.
- **Option 3 (Ansible facts delegation)**: Run a pre-task that queries a CMDB/service registry for nodes with role `app_server` in the target environment, then construct the backends dict dynamically using `set_fact` with `combine`.

---

## Checks for the Migration

**Files to verify after migration**:
- `/etc/haproxy/haproxy.cfg` — main config, mode `0640`, group `haproxy`
- `/etc/haproxy/conf.d/webservers.cfg` — webservers backend fragment
- `/etc/haproxy/conf.d/api.cfg` — api backend fragment
- `/etc/haproxy/conf.d/internal_monitoring.cfg` — monitoring backend fragment (haproxy_prod_fra cluster only)
- `/etc/haproxy/conf.d/stick-tables.cfg` — stick table config (production only)
- `/etc/haproxy/errors/503.http` — custom error page, source: `puppet:///modules/profile_haproxy/haproxy_errors/503.http`
- `/etc/haproxy/errors/408.http` — custom error page, source: `puppet:///modules/profile_haproxy/haproxy_errors/408.http`
- `/etc/logrotate.d/haproxy` — logrotate config, mode `0644`, owner `root`, group `root`
- `/var/lib/haproxy/` — directory, owner `haproxy`, group `haproxy`, mode `0750`
- `/etc/haproxy/errors/` — directory, owner `root`, group `haproxy`, mode `0755`

**Service endpoints to check**:
- Port `80` (HTTP frontend) — `curl -I http://<lb-ip>/`
- Port `443` (HTTPS frontend, production) — `curl -Ik https://<lb-ip>/`
- Port `9001` (stats, lb01 only) — `curl http://<lb-ip>:9001/haproxy-stats` with basic auth `admin:<password>`
- Unix socket `/var/lib/haproxy/stats` — `echo "show info" | socat stdio /var/lib/haproxy/stats`

**Templates rendered**:
- `site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb` → `/etc/haproxy/haproxy.cfg` — rendered **1 time** per node
- `site/modules/linux/profile_haproxy/templates/backend.conf.epp` → `/etc/haproxy/conf.d/webservers.cfg` — rendered **1 time**
- `site/modules/linux/profile_haproxy/templates/backend.conf.epp` → `/etc/haproxy/conf.d/api.cfg` — rendered **1 time**
- `site/modules/linux/profile_haproxy/templates/backend.conf.epp` → `/etc/haproxy/conf.d/internal_monitoring.cfg` — rendered **1 time** (haproxy_prod_fra cluster only)

## Pre-flight checks:
```bash
# HAProxy config validation
haproxy -c -f /etc/haproxy/haproxy.cfg

# Service status
systemctl status haproxy

# HAProxy version
haproxy -v 2>&1 | grep -oP 'version\s+\K[\d.]+'

# Main config file permissions (expect 640, group haproxy)
stat -c "%a %U %G" /etc/haproxy/haproxy.cfg

# Backend fragment files
stat -c "%a %U %G" /etc/haproxy/conf.d/webservers.cfg
stat -c "%a %U %G" /etc/haproxy/conf.d/api.cfg
stat -c "%a %U %G" /etc/haproxy/conf.d/internal_monitoring.cfg

# Stick-tables config (production only)
stat -c "%a %U %G" /etc/haproxy/conf.d/stick-tables.cfg

# Error pages
stat -c "%a %U %G" /etc/haproxy/errors/503.http
stat -c "%a %U %G" /etc/haproxy/errors/408.http

# Logrotate config
stat -c "%a %U %G" /etc/logrotate.d/haproxy

# haproxy user/group
id haproxy
getent group haproxy

# var/lib/haproxy directory (expect 750, owner haproxy)
stat -c "%a %U %G" /var/lib/haproxy

# HTTP frontend
curl -I http://<lb-ip>/

# HTTPS frontend (production)
curl -Ik https://<lb-ip>/

# Stats endpoint (lb01 only, port 9001)
curl -u admin:<password> http://<lb-ip>:9001/haproxy-stats

# HAProxy runtime socket
echo "show info" | socat stdio /var/lib/haproxy/stats
echo "show servers state" | socat stdio /var/lib/haproxy/stats

# SELinux boolean (RedHat only)
getsebool haproxy_connect_any

# Firewall ports (RedHat / firewalld)
firewall-cmd --zone=public --list-ports
firewall-cmd --zone=public --query-port=80/tcp
firewall-cmd --zone=public --query-port=443/tcp
firewall-cmd --zone=public --query-port=9001/tcp

# Firewall ports (Debian / ufw)
ufw status
ufw status | grep -E "80/tcp|443/tcp|9001/tcp"
```