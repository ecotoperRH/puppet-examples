---
source-path: modules/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module configures HAProxy as a load balancer with support for multiple backends, SSL termination, and statistics monitoring. It manages the installation, configuration, service, and firewall rules for HAProxy instances. The module uses a hierarchical Hiera structure to configure environment-specific settings and backend server definitions.

## Service Type and Instances

**Service Type**: Load Balancer (HAProxy)

**Configured Instances**:
- **HAProxy**: HTTP/HTTPS load balancer
  - Location/Path: /etc/haproxy
  - Ports: 80 (HTTP), 443 (HTTPS), 9000/9001 (Stats)
  - Key Config: Multiple backends with health checks, SSL termination, stick tables for session persistence

## File Structure

```
modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml
modules/profile_haproxy/data/common.yaml
modules/profile_haproxy/data/datacenter/dc1_fra.yaml
modules/profile_haproxy/data/environment/production.yaml
modules/profile_haproxy/data/environment/staging.yaml
modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml
modules/profile_haproxy/data/os/Debian.yaml
modules/profile_haproxy/lib/facter/haproxy_version.rb
modules/profile_haproxy/manifests/config.pp
modules/profile_haproxy/manifests/firewall.pp
modules/profile_haproxy/manifests/init.pp
modules/profile_haproxy/manifests/install.pp
modules/profile_haproxy/manifests/service.pp
modules/profile_haproxy/templates/backend.conf.epp
modules/profile_haproxy/templates/haproxy.cfg.erb
```

## Module Explanation

The module performs operations in this order:

1. **profile_haproxy** (`manifests/init.pp`):
   - Sets class parameters from Hiera: package_name='haproxy', config_dir='/etc/haproxy', config_file='/etc/haproxy/haproxy.cfg', service_name='haproxy', user='haproxy', group='haproxy', stats_enabled=true/false (environment dependent), stats_port=9000/9001, stats_uri='/haproxy-stats', stats_user='admin', stats_password=(encrypted), global_maxconn=4096/16384/32768 (environment dependent), client_timeout='30s'/'60s', server_timeout='30s'/'60s', connect_timeout='5s', retries=3, ssl_enabled=false/true (environment dependent), ssl_cert_path='/etc/ssl/certs', ssl_key_path='/etc/ssl/private', ssl_ciphers='ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256', ssl_min_version='TLSv1.2'/'TLSv1.3', log_server='127.0.0.1'/'10.100.1.50', log_facility='local0', log_level='info'/'warning'/'debug', backends=(hash of backend configurations)
   - Contains profile_haproxy::install
   - Contains profile_haproxy::config
   - Contains profile_haproxy::service
   - Contains profile_haproxy::firewall
   - Sets ordering: install -> config ~> service (config changes notify service restart)
   - Resources: None (orchestration only)

2. **profile_haproxy::install** (`manifests/install.pp`):
   - Installs package: haproxy
   - Installs extra packages from Hiera: hatop (on Debian)
   - Creates haproxy group (system: true)
   - Creates haproxy user (gid: haproxy, home: /var/lib/haproxy, shell: /sbin/nologin, system: true)
   - Creates directories:
     - /etc/haproxy (owner: root, group: haproxy, mode: 0755)
     - /etc/haproxy/conf.d (owner: root, group: haproxy, mode: 0755)
     - /var/lib/haproxy (owner: haproxy, group: haproxy, mode: 0750)
   - Resources: package (2), user (1), group (1), file/directory (3)

3. **profile_haproxy::config** (`manifests/config.pp`):
   - Deploys main HAProxy configuration:
     - Template: haproxy.cfg.erb → /etc/haproxy/haproxy.cfg (mode: 0640, owner: root, group: haproxy)
     - Sets: global_maxconn, timeouts, SSL settings, stats configuration
   - Iterations: Runs 3 times for backends defined in Hiera ($backends hash): webservers, api, internal_monitoring
     - **webservers**:
       - Balance method: roundrobin
       - Port: 8080
       - Health check: httpchk GET /health
       - Health interval: 5s
       - Servers:
         - web1-fra: 10.100.1.10:8080, weight: 100
         - web2-fra: 10.100.1.11:8080, weight: 100
         - web3-fra: 10.100.1.12:8080, weight: 100
       - Deploys backend config: backend.conf.epp → /etc/haproxy/conf.d/webservers.cfg (mode: 0640)
     - **api**:
       - Balance method: leastconn
       - Port: 3000
       - Health check: httpchk GET /api/health
       - Health interval: 10s
       - Servers:
         - api1-fra: 10.100.2.10:3000, weight: 200 (on lb01.fra.example.com) or 100 (elsewhere)
         - api2-fra: 10.100.2.11:3000, weight: 100
       - Deploys backend config: backend.conf.epp → /etc/haproxy/conf.d/api.cfg (mode: 0640)
     - **internal_monitoring** (only in haproxy_prod_fra cluster):
       - Balance method: roundrobin
       - Port: 9090
       - Health check: httpchk GET /-/healthy
       - Health interval: 15s
       - Servers:
         - prom1-fra: 10.100.3.10:9090, weight: 100
       - Deploys backend config: backend.conf.epp → /etc/haproxy/conf.d/internal_monitoring.cfg (mode: 0640)
   - Deploys custom error pages:
     - Creates directory: /etc/haproxy/errors (owner: root, group: haproxy, mode: 0755)
     - Deploys error pages:
       - 503.http → /etc/haproxy/errors/503.http (mode: 0644)
       - 408.http → /etc/haproxy/errors/408.http (mode: 0644)
   - Conditionally configures stick tables (production only):
     - If stick_table_enabled=true:
       - Deploys stick-tables.cfg → /etc/haproxy/conf.d/stick-tables.cfg (mode: 0640)
       - Sets: stick-table type ip size 200k expire 30m
   - Resources: file (7-8 depending on environment)
   - **notifies**: file[/etc/haproxy/haproxy.cfg] ~> Class['profile_haproxy::service']
   - **notifies**: file[/etc/haproxy/conf.d/*.cfg] ~> Class['profile_haproxy::service']

4. **profile_haproxy::service** (`manifests/service.pp`):
   - Creates validation check for HAProxy config:
     - Exec: haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/ (refreshonly: true)
   - Creates systemd override directory:
     - /etc/systemd/system/haproxy.service.d (owner: root, group: root, mode: 0755)
   - Deploys systemd override file:
     - /etc/systemd/system/haproxy.service.d/override.conf (owner: root, group: root, mode: 0644)
     - Sets ExecStart to load both main config and conf.d directory
   - Runs systemd daemon-reload when override changes
   - Manages service: haproxy
     - ensure: running
     - enable: true
     - hasrestart: true
     - hasstatus: true
   - Deploys logrotate configuration:
     - /etc/logrotate.d/haproxy (owner: root, group: root, mode: 0644)
     - Sets: daily rotation, 14 day retention, compression
   - Resources: exec (2), file (3), service (1)

5. **profile_haproxy::firewall** (`manifests/firewall.pp`):
   - Installs package: ufw (on Debian)
   - Configures firewall rules:
     - Allow TCP port 80 (HTTP)
     - Allow TCP port 443 (HTTPS)
     - Allow TCP port 9000/9001 (Stats, if stats_enabled=true)
     - Enables UFW firewall
   - Resources: package (1), exec (3-4 depending on stats_enabled)

## Variables

**Variable Flow Summary**: 26 variables across 7 Hiera levels with deep merge for backend configurations

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
- `profile_haproxy::stats_password`: `ENC[PKCS7,MIIBygYJKoZIhvcNAQcDoIIBuzCCAbcCAQAxggEhMIIBHQIBADAFMAACAQEwDQYJKoZIhvcNAQEBBQAEggEAExample]` (type: string, encrypted)
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
  ```yaml
  webservers:
    balance: roundrobin
    port: 8080
    health_check: httpchk GET /health
    health_interval: 5s
    servers:
      - name: web1
        address: 10.0.1.10
        weight: 100
      - name: web2
        address: 10.0.1.11
        weight: 100
      - name: web3
        address: 10.0.1.12
        weight: 100
  api:
    balance: leastconn
    port: 3000
    health_check: httpchk GET /api/health
    health_interval: 10s
    servers:
      - name: api1
        address: 10.0.2.10
        weight: 100
      - name: api2
        address: 10.0.2.11
        weight: 100
  ```

**os/Debian.yaml (OS-specific overrides)** → Migration note: OS-specific variables, loaded conditionally based on OS family
- `profile_haproxy::package_name`: `haproxy` (type: string)
- `profile_haproxy::config_dir`: `/etc/haproxy` (type: string)
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::extra_packages`: `[hatop]` (type: array)

**environment/production.yaml (environment overrides)** → Migration note: Environment-specific variables, loaded based on deployment environment
- `profile_haproxy::global_maxconn`: `16384` (type: integer)
- `profile_haproxy::ssl_enabled`: `true` (type: boolean)
- `profile_haproxy::log_level`: `warning` (type: string)
- `profile_haproxy::client_timeout`: `60s` (type: string)
- `profile_haproxy::server_timeout`: `60s` (type: string)
- `profile_haproxy::stats_enabled`: `false` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_size`: `200k` (type: string)
- `profile_haproxy::stick_table_expire`: `30m` (type: string)

**environment/staging.yaml (environment overrides)** → Migration note: Environment-specific variables, loaded based on deployment environment
- `profile_haproxy::global_maxconn`: `2048` (type: integer)
- `profile_haproxy::ssl_enabled`: `false` (type: boolean)
- `profile_haproxy::log_level`: `debug` (type: string)
- `profile_haproxy::stats_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `false` (type: boolean)

**datacenter/dc1_fra.yaml (datacenter overrides)** → Migration note: Datacenter-specific variables, loaded based on datacenter fact
- `profile_haproxy::log_server`: `10.100.1.50` (type: string)
- `profile_haproxy::ntp_servers`: `[ntp1.dc1.fra.example.com, ntp2.dc1.fra.example.com]` (type: array)
- `profile_haproxy::backends`: (type: hash, deep merged)
  ```yaml
  webservers:
    servers:
      - name: web1-fra
        address: 10.100.1.10
        weight: 100
      - name: web2-fra
        address: 10.100.1.11
        weight: 100
      - name: web3-fra
        address: 10.100.1.12
        weight: 100
  api:
    servers:
      - name: api1-fra
        address: 10.100.2.10
        weight: 100
      - name: api2-fra
        address: 10.100.2.11
        weight: 100
  ```

**cluster/haproxy_prod_fra.yaml (cluster overrides)** → Migration note: Cluster-specific variables, loaded based on cluster fact
- `profile_haproxy::global_maxconn`: `32768` (type: integer)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (type: string)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (type: string)
- `profile_haproxy::backends`: (type: hash, deep merged)
  ```yaml
  internal_monitoring:
    balance: roundrobin
    port: 9090
    health_check: httpchk GET /-/healthy
    health_interval: 15s
    servers:
      - name: prom1-fra
        address: 10.100.3.10
        weight: 100
  ```

**nodes/lb01.fra.example.com.yaml (node-specific overrides)** → Migration note: Node-specific variables, loaded based on node name
- `profile_haproxy::stats_enabled`: `true` (type: boolean)
- `profile_haproxy::stats_port`: `9001` (type: integer)
- `profile_haproxy::backends`: (type: hash, deep merged)
  ```yaml
  api:
    servers:
      - name: api1-fra
        address: 10.100.2.10
        weight: 200
      - name: api2-fra
        address: 10.100.2.11
        weight: 100
  ```

### Variable Migration Summary

- **Common defaults**: 25 variables from common.yaml (base configuration for all nodes)
- **OS-specific variables**: 3 variables that vary by operating system family
- **Environment-specific variables**: 9 variables that vary by deployment environment (production, staging)
- **Datacenter-specific variables**: 3 variables that vary by datacenter
- **Cluster-specific variables**: 4 variables that vary by cluster
- **Host-specific variables**: 3 variables for individual host overrides
- **Encrypted variables**: 1 variable that is encrypted (eyaml) and needs secure storage

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **profile_haproxy::global_maxconn**: defined at common, environment, cluster levels, merge strategy: first
- **profile_haproxy::ssl_enabled**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::log_level**: defined at common, environment levels, merge strategy: first
- **profile_haproxy::stats_enabled**: defined at common, environment, node levels, merge strategy: first
- **profile_haproxy::stats_port**: defined at common, node levels, merge strategy: first
- **profile_haproxy::ssl_ciphers**: defined at common, cluster levels, merge strategy: first
- **profile_haproxy::ssl_min_version**: defined at common, cluster levels, merge strategy: first
- **profile_haproxy::log_server**: defined at common, datacenter levels, merge strategy: first
- **profile_haproxy::backends**: defined at common, datacenter, cluster, node levels, merge strategy: deep

### Merge Strategy Notes

- Variables using `deep` merge - Hash values are recursively merged (deep merge)
  - profile_haproxy::backends - Backend configurations are merged across hierarchy levels
- Variables using `first` (default) - First value found wins, no merging
  - All other variables use first-found strategy

## Custom Types and Providers

### Custom Fact: haproxy_version
- **Name**: haproxy_version
- **Purpose**: Retrieves the installed HAProxy version
- **Implementation**: Executes 'haproxy -v' and extracts version using regex
- **Platform constraints**: Linux only (confine kernel: 'Linux')
- **Migration notes**: Create an equivalent Ansible fact that runs the same command and extracts the version number. This can be implemented as a custom fact in Ansible or as a task that registers the output of the command.

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (forge, version: 9.7.0)
- puppetlabs-concat (forge, version: 9.0.2)
- puppetlabs-firewall (forge, version: 8.1.3)
- puppetlabs-vcsrepo (forge, version: 6.1.0)
- puppet-redis (forge, version: 11.0.0)
- puppetlabs-apt (forge, version: 9.4.0)

**System package dependencies**:
- haproxy
- hatop (on Debian)
- ufw (on Debian)

**Service dependencies**:
- HAProxy service depends on configuration validation

## Puppet Facts Used

- `$facts['kernel']` - Kernel type (Linux)
- `$facts['os']['family']` - Operating system family (Debian)
- `$facts['os']['name']` - Operating system name
- `$facts['os']['release']['full']` - OS version
- `$facts['os']['release']['major']` - OS major version
- `$facts['architecture']` - CPU architecture
- `$facts['is_virtual']` - Whether system is virtualized
- `$facts['virtual']` - Virtualization type
- `$::environment` - Puppet environment (production, staging)
- `$::datacenter` - Datacenter location (dc1_fra)
- `$::cluster_name` - Cluster name (haproxy_prod_fra)
- `$::trusted.certname` - Node certificate name (lb01.fra.example.com)

## Template Conversion Notes

### haproxy.cfg.erb
- **Variables used**: log_server, log_facility, log_level, global_maxconn, user, group, ssl_enabled, ssl_ciphers, connect_timeout, client_timeout, server_timeout, retries, stats_enabled, stats_port, stats_uri, stats_user, stats_password, ssl_cert_path, backends
- **Conditional rendering**: SSL configuration is conditionally included based on ssl_enabled
- **Conditional rendering**: Stats page is conditionally included based on stats_enabled
- **Iterations**: Loops through backends hash to reference backend configurations
- **Migration notes**: Convert ERB template to Jinja2 syntax, replacing <% %> with {% %} and <%= %> with {{ }}

### backend.conf.epp
- **Variables used**: backend_name, balance, port, servers, health_check, health_interval, ssl_enabled
- **Conditional rendering**: Health check options are conditionally included
- **Iterations**: Loops through servers array to generate server lines
- **Migration notes**: Convert EPP template to Jinja2 syntax, replacing <%- -%> with {% %} and <%= %> with {{ }}

## Checks for the Migration

**Files to verify**:
- /etc/haproxy/haproxy.cfg
- /etc/haproxy/conf.d/webservers.cfg
- /etc/haproxy/conf.d/api.cfg
- /etc/haproxy/conf.d/internal_monitoring.cfg (if in haproxy_prod_fra cluster)
- /etc/haproxy/conf.d/stick-tables.cfg (if in production environment)
- /etc/systemd/system/haproxy.service.d/override.conf
- /etc/logrotate.d/haproxy

**Service endpoints to check**:
- HTTP: port 80
- HTTPS: port 443 (if ssl_enabled=true)
- Stats: port 9000/9001 (if stats_enabled=true)

**Templates rendered**:
- haproxy.cfg.erb → /etc/haproxy/haproxy.cfg (1 instance)
- backend.conf.epp → /etc/haproxy/conf.d/webservers.cfg (1 instance)
- backend.conf.epp → /etc/haproxy/conf.d/api.cfg (1 instance)
- backend.conf.epp → /etc/haproxy/conf.d/internal_monitoring.cfg (1 instance, if in haproxy_prod_fra cluster)

## Pre-flight checks:
```bash
# Service status commands
systemctl status haproxy

# Instance-specific checks
haproxy -c -f /etc/haproxy/haproxy.cfg -f /etc/haproxy/conf.d/
curl -I http://localhost/
curl -I https://localhost/ # if ssl_enabled=true
curl http://localhost:9000/haproxy-stats # if stats_enabled=true on standard nodes
curl http://localhost:9001/haproxy-stats # if on lb01.fra.example.com

# Configuration validation commands
ufw status
```