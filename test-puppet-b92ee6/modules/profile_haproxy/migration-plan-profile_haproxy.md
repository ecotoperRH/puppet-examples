---
source-path: modules/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module configures HAProxy as a load balancer with multiple backends, SSL support, statistics page, and firewall rules. It manages the installation, configuration, service, and firewall aspects of HAProxy with a focus on high availability and performance.

## Service Type and Instances

**Service Type**: Load Balancer (HAProxy)

**Configured Instances**:
- **webservers**: Web server load balancing
  - Location/Path: /etc/haproxy/conf.d/webservers.cfg
  - Port/Socket: 8080
  - Key Config: roundrobin balancing, 3 backend servers
- **api**: API service load balancing
  - Location/Path: /etc/haproxy/conf.d/api.cfg
  - Port/Socket: 3000
  - Key Config: leastconn balancing, 2 backend servers
- **internal_monitoring**: Monitoring service (production cluster only)
  - Location/Path: /etc/haproxy/conf.d/internal_monitoring.cfg
  - Port/Socket: 9090
  - Key Config: roundrobin balancing, 1 backend server

## File Structure

- **Manifests**:
  - modules/profile_haproxy/manifests/init.pp
  - modules/profile_haproxy/manifests/install.pp
  - modules/profile_haproxy/manifests/config.pp
  - modules/profile_haproxy/manifests/service.pp
  - modules/profile_haproxy/manifests/firewall.pp
  - site/profile/manifests/loadbalancer/haproxy.pp
  - site/role/manifests/haproxy.pp

- **Templates**:
  - modules/profile_haproxy/templates/haproxy.cfg.erb
  - modules/profile_haproxy/templates/backend.conf.epp

- **Data**:
  - modules/profile_haproxy/data/common.yaml
  - modules/profile_haproxy/data/os/Debian.yaml
  - modules/profile_haproxy/data/environment/production.yaml
  - modules/profile_haproxy/data/environment/staging.yaml
  - modules/profile_haproxy/data/datacenter/dc1_fra.yaml
  - modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml
  - modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml

- **Custom Facts**:
  - modules/profile_haproxy/lib/facter/haproxy_version.rb

## Module Explanation

The module performs operations in this order:

1. **role::haproxy** (`site/role/manifests/haproxy.pp`):
   - `conditional` → if $facts['kernel'].downcase == 'linux' executes a command
   - `include profile::base::base` (base system configuration)
   - `include profile::loadbalancer::haproxy`
   - `ordering` → Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']

2. **profile::loadbalancer::haproxy** (`site/profile/manifests/loadbalancer/haproxy.pp`):
   - `include profile_haproxy`

3. **profile_haproxy** (`modules/profile_haproxy/manifests/init.pp`):
   - Sets class parameters from Hiera:
     - package_name: `haproxy`
     - config_dir: `/etc/haproxy`
     - config_file: `/etc/haproxy/haproxy.cfg`
     - service_name: `haproxy`
     - user: `haproxy`
     - group: `haproxy`
     - stats_enabled: `true` (default), `false` (production)
     - stats_port: `9000`
     - stats_uri: `/haproxy-stats`
     - stats_user: `admin`
     - stats_password: `[encrypted]`
     - global_maxconn: `4096` (default), `16384` (production), `32768` (cluster)
     - client_timeout: `30s` (default), `60s` (production)
     - server_timeout: `30s` (default), `60s` (production)
     - connect_timeout: `5s`
     - retries: `3`
     - ssl_enabled: `false` (default), `true` (production)
     - ssl_cert_path: `/etc/ssl/certs`
     - ssl_key_path: `/etc/ssl/private`
     - ssl_ciphers: `ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256` (default), `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (cluster)
     - ssl_min_version: `TLSv1.2` (default), `TLSv1.3` (cluster)
     - log_server: `127.0.0.1`
     - log_facility: `local0`
     - log_level: `info` (default), `warning` (production)
     - backends: Hash of backend configurations (merged deeply across hierarchy)
   - `contain profile_haproxy::install`
   - `contain profile_haproxy::config`
   - `contain profile_haproxy::service`
   - `contain profile_haproxy::firewall`
   - `ordering` → Class['profile_haproxy::install'] -> Class['profile_haproxy::config'] ~> Class['profile_haproxy::service']

4. **profile_haproxy::install** (`modules/profile_haproxy/manifests/install.pp`):
   - `package 'haproxy'` → ensure: `present`
   - `conditional` → if !empty($extra_packages)
     - `package ['hatop']` → ensure: `present`
   - `group 'haproxy'` → ensure: `present`
   - `user 'haproxy'` → ensure: `present`, gid: `haproxy`
   - `file ['/etc/haproxy', '/etc/haproxy/conf.d']` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0755`
   - `file '/var/lib/haproxy'` → ensure: `directory`, owner: `haproxy`, group: `haproxy`, mode: `0755`

5. **profile_haproxy::config** (`modules/profile_haproxy/manifests/config.pp`):
   - `file '/etc/haproxy/haproxy.cfg'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
     - Template: `profile_haproxy/haproxy.cfg.erb`
     - Variables: package_name, config_dir, user, group, global_maxconn, stats_enabled, stats_port, stats_uri, stats_user, stats_password, client_timeout, server_timeout, connect_timeout, retries, ssl_enabled, ssl_cert_path, ssl_key_path, ssl_ciphers, ssl_min_version, log_server, log_facility, log_level
   - **webservers**:
     - `file '/etc/haproxy/conf.d/webservers.cfg'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
       - Template: `profile_haproxy/backend.conf.epp`
       - Variables: name=webservers, balance=roundrobin, port=8080, health_check=httpchk GET /health, health_interval=5s, servers=[{name: web1, address: 10.0.1.10, weight: 100}, {name: web2, address: 10.0.1.11, weight: 100}, {name: web3, address: 10.0.1.12, weight: 100}]
   - **api**:
     - `file '/etc/haproxy/conf.d/api.cfg'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
       - Template: `profile_haproxy/backend.conf.epp`
       - Variables: name=api, balance=leastconn, port=3000, health_check=httpchk GET /api/health, health_interval=10s, servers=[{name: api1, address: 10.0.2.10, weight: 100}, {name: api2, address: 10.0.2.11, weight: 100}]
   - **internal_monitoring**:
     - `file '/etc/haproxy/conf.d/internal_monitoring.cfg'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
       - Template: `profile_haproxy/backend.conf.epp`
       - Variables: name=internal_monitoring, balance=roundrobin, port=9090, health_check=httpchk GET /-/healthy, health_interval=15s, servers=[{name: prom1-fra, address: 10.100.3.10, weight: 100}]
   - **503**:
     - `file '/etc/haproxy/errors/503.http'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
   - **408**:
     - `file '/etc/haproxy/errors/408.http'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
   - `file '/etc/haproxy/errors'` → ensure: `directory`, owner: `root`, group: `root`, mode: `0755`
   - `conditional` → if $stick_table_enabled (true in production)
     - `file '/etc/haproxy/conf.d/stick-tables.cfg'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
       - Variables: stick_table_size=200k, stick_table_expire=30m

6. **profile_haproxy::service** (`modules/profile_haproxy/manifests/service.pp`):
   - `exec 'haproxy_config_check'` → command: `/usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg`, refreshonly: `true`
   - `file '/etc/systemd/system/haproxy.service.d'` → ensure: `directory`, owner: `root`, group: `root`, mode: `0755`
   - `file '/etc/systemd/system/haproxy.service.d/override.conf'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template
   - `exec 'haproxy_systemd_daemon_reload'` → command: `/bin/systemctl daemon-reload`, refreshonly: `true`
   - `service 'haproxy'` → ensure: `running`, enable: `true`, hasrestart: `true`, hasstatus: `true`
   - `file '/etc/logrotate.d/haproxy'` → ensure: `file`, owner: `root`, group: `root`, mode: `0644`, content: template

7. **profile_haproxy::firewall** (`modules/profile_haproxy/manifests/firewall.pp`):
   - `conditional` → if $firewall_provider == 'ufw' (true for Debian)
     - `package 'ufw'` → ensure: `present`
     - `exec 'ufw_allow_http'` → command: `/usr/sbin/ufw allow http`, unless: `/usr/sbin/ufw status | grep "80/tcp.*ALLOW"`
     - `exec 'ufw_allow_https'` → command: `/usr/sbin/ufw allow https`, unless: `/usr/sbin/ufw status | grep "443/tcp.*ALLOW"`
     - `exec 'ufw_enable'` → command: `/usr/sbin/ufw --force enable`, unless: `/usr/sbin/ufw status | grep "Status: active"`

## Variables

**Variable Flow Summary**: 24 variables across 7 Hiera levels

### Variable Definitions

**common.yaml (defaults)** → Migration note: Base defaults for all nodes
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
- `profile_haproxy::stats_password`: `[encrypted]` (type: string)
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
- `profile_haproxy::backends`: (type: hash)
  - `webservers`: (type: hash)
    - `balance`: `roundrobin` (type: string)
    - `port`: `8080` (type: integer)
    - `health_check`: `httpchk GET /health` (type: string)
    - `health_interval`: `5s` (type: string)
    - `servers`: (type: array)
      - `name`: `web1`, `address`: `10.0.1.10`, `weight`: `100`
      - `name`: `web2`, `address`: `10.0.1.11`, `weight`: `100`
      - `name`: `web3`, `address`: `10.0.1.12`, `weight`: `100`
  - `api`: (type: hash)
    - `balance`: `leastconn` (type: string)
    - `port`: `3000` (type: integer)
    - `health_check`: `httpchk GET /api/health` (type: string)
    - `health_interval`: `10s` (type: string)
    - `servers`: (type: array)
      - `name`: `api1`, `address`: `10.0.2.10`, `weight`: `100`
      - `name`: `api2`, `address`: `10.0.2.11`, `weight`: `100`

**os/Debian.yaml (OS-specific)** → Migration note: OS-specific variables, loaded conditionally based on OS family
- `profile_haproxy::package_name`: `haproxy` (type: string)
- `profile_haproxy::config_dir`: `/etc/haproxy` (type: string)
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::extra_packages`: `['hatop']` (type: array)

**environment/production.yaml** → Migration note: Production environment overrides
- `profile_haproxy::global_maxconn`: `16384` (type: integer)
- `profile_haproxy::ssl_enabled`: `true` (type: boolean)
- `profile_haproxy::log_level`: `warning` (type: string)
- `profile_haproxy::client_timeout`: `60s` (type: string)
- `profile_haproxy::server_timeout`: `60s` (type: string)
- `profile_haproxy::stats_enabled`: `false` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_size`: `200k` (type: string)
- `profile_haproxy::stick_table_expire`: `30m` (type: string)

**cluster/haproxy_prod_fra.yaml** → Migration note: Cluster-specific overrides for Frankfurt production
- `profile_haproxy::global_maxconn`: `32768` (type: integer)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (type: string)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (type: string)
- `profile_haproxy::backends`: (type: hash)
  - `internal_monitoring`: (type: hash)
    - `balance`: `roundrobin` (type: string)
    - `port`: `9090` (type: integer)
    - `health_check`: `httpchk GET /-/healthy` (type: string)
    - `health_interval`: `15s` (type: string)
    - `servers`: (type: array)
      - `name`: `prom1-fra`, `address`: `10.100.3.10`, `weight`: `100`

### Variable Migration Summary

- **Common defaults**: 24 variables from common.yaml (base configuration for all nodes)
- **OS-specific variables**: 4 variables that vary by operating system family
- **Environment-specific variables**: 9 variables that vary by deployment environment (dev, staging, prod)
- **Cluster-specific**: 4 variables for specific cluster configurations
- **Encrypted variables**: 1 variable needing secure storage (stats_password)

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **profile_haproxy::global_maxconn**: defined at common, environment, cluster levels, merge strategy: first
- **profile_haproxy::ssl_enabled**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::ssl_ciphers**: defined at common, cluster levels, merge strategy: first
- **profile_haproxy::ssl_min_version**: defined at common, cluster levels, merge strategy: first
- **profile_haproxy::log_level**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::client_timeout**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::server_timeout**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::stats_enabled**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::backends**: defined at common, cluster levels, merge strategy: deep

### Merge Strategy Notes

- Variables using `hash` merge - Hash values from multiple levels are merged (shallow merge)
- Variables using `deep` merge - Hash values are recursively merged (deep merge)
- Variables using `first` (default) - First value found wins, no merging

## Custom Types and Providers

**haproxy_version fact**:
- File: modules/profile_haproxy/lib/facter/haproxy_version.rb
- Description: Detects the installed HAProxy version by executing 'haproxy -v' and parsing the version number from the output.

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (version: 9.7.0)
- puppetlabs-concat (version: 9.0.2)
- puppetlabs-firewall (version: 8.1.3)
- puppetlabs-vcsrepo (version: 6.1.0)
- puppet-redis (version: 11.0.0)
- puppetlabs-apt (version: 9.4.0)

**System package dependencies**:
- haproxy
- hatop (on Debian)
- ufw (on Debian)

**Service dependencies**:
- systemd (for service management)
- logrotate (for log rotation)

## Puppet Facts Used

- `$facts['kernel']`: Determines if the system is Linux
- `$facts['os']['family']`: Used for OS-specific configurations (Debian)
- `$facts['os']['name']`: Used for OS-specific configurations
- `$facts['architecture']`: Used in Hiera hierarchy
- `$facts['is_virtual']`: Used in Hiera hierarchy
- `$facts['virtual']`: Used in Hiera hierarchy

## Template Conversion Notes

**haproxy.cfg.erb**:
- Contains 19 variables and 3 logic blocks
- Main configuration template for HAProxy
- Includes global settings, defaults, frontend and backend configurations
- Conditional blocks for SSL configuration, stats page, and logging

**backend.conf.epp**:
- Contains 10 variables and 3 logic blocks
- Used for each backend configuration
- Includes server definitions, health checks, and balancing method
- Rendered once per backend (3 times total)

## Checks for the Migration

**Files to verify**:
- /etc/haproxy/haproxy.cfg
- /etc/haproxy/conf.d/webservers.cfg
- /etc/haproxy/conf.d/api.cfg
- /etc/haproxy/conf.d/internal_monitoring.cfg (production only)
- /etc/haproxy/conf.d/stick-tables.cfg (production only)
- /etc/haproxy/errors/503.http
- /etc/haproxy/errors/408.http
- /etc/systemd/system/haproxy.service.d/override.conf
- /etc/logrotate.d/haproxy

**Service endpoints to check**:
- HTTP (port 80)
- HTTPS (port 443)
- Stats page (port 9000, path /haproxy-stats, disabled in production)

**Templates rendered**:
- haproxy.cfg.erb (1 time)
- backend.conf.epp (3 times: webservers, api, internal_monitoring)
- error pages (2 times: 503.http, 408.http)
- stick-tables.cfg (1 time, production only)

## Pre-flight checks:
```bash
# Service status commands
systemctl status haproxy

# Instance-specific checks
# Webservers backend
curl -I http://localhost:8080/health
# API backend
curl -I http://localhost:3000/api/health
# Internal monitoring backend (production only)
curl -I http://localhost:9090/-/healthy

# Configuration validation commands
haproxy -c -f /etc/haproxy/haproxy.cfg

# Network/connectivity checks
ufw status
netstat -tulpn | grep haproxy
```