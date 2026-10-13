---
source-path: modules/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: `profile_haproxy` installs and configures HAProxy on Debian-family Linux systems. It manages the HAProxy service, global and frontend configuration, dynamically generated backend fragments, custom error files, optional stick tables, systemd overrides, log rotation, and UFW rules. The intended effective target is production node `lb01.fra.example.com` in the Frankfurt cluster, with HAProxy on ports `80`, `443`, and statistics port `9001`. Hiera values, encryption metadata, and final backend resolution require verification against the source data files before migration.

## Service Type and Instances

**Service Type**: HTTP/HTTPS load balancer and reverse proxy.

**Configured Instances**:

- **HAProxy service**
  - Service: `haproxy`
  - Location/Path: `/etc/haproxy/haproxy.cfg`
  - Fragment directory: `/etc/haproxy/conf.d`
  - Error directory: `/etc/haproxy/errors`
  - Runtime directory: `/var/lib/haproxy`
  - Runtime user/group: `haproxy:haproxy`
  - Frontend ports: `80`, `443`
  - Statistics port: `9001` on the intended production node
  - Statistics URI: `/haproxy-stats`
  - Runtime socket: `/var/lib/haproxy/stats`

- **webservers backend**
  - Purpose: Routes HTTP traffic to web servers
  - Load-balancing method: `roundrobin`
  - Backend port: `8080`
  - Health check: `GET /health`
  - Health interval: `5s`
  - Servers:
    - `web1`: `10.0.1.10:8080`, weight `100`
    - `web2`: `10.0.1.11:8080`, weight `100`
    - `web3`: `10.0.1.12:8080`, weight `100`

- **api backend**
  - Purpose: Routes API traffic
  - Load-balancing method: `leastconn`
  - Backend port: `3000`
  - Health check: `GET /api/health`
  - Health interval: `10s`
  - Intended effective servers:
    - `api1-fra`: `10.100.2.10:3000`, weight `200`
    - `api2-fra`: `10.100.2.11:3000`, weight `100`
  - Migration note: The node-level `api.servers` list must be handled explicitly in Ansible. Puppet Hiera deep merge does not automatically define Ansible list-merging behavior.

- **internal_monitoring backend**
  - Purpose: Routes monitoring traffic
  - Load-balancing method: `roundrobin`
  - Backend port: `9090`
  - Health check: `GET /-/healthy`
  - Health interval: `15s`
  - Servers:
    - `prom1-fra`: `10.100.3.10:9090`, weight `100`

- **HAProxy statistics listener**
  - Purpose: Exposes the HAProxy statistics interface
  - Port: `9001`
  - URI: `/haproxy-stats`
  - User: `admin`
  - Password: Encrypted secret metadata and value require source-file verification.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
### Manifests

- `site/role/manifests/haproxy.pp`
- `site/profile/manifests/loadbalancer/haproxy.pp`
- `modules/profile_haproxy/manifests/init.pp`
- `modules/profile_haproxy/manifests/install.pp`
- `modules/profile_haproxy/manifests/config.pp`
- `modules/profile_haproxy/manifests/service.pp`
- `modules/profile_haproxy/manifests/firewall.pp`

### Templates

- `modules/profile_haproxy/templates/haproxy.cfg.erb`
- `modules/profile_haproxy/templates/backend.conf.epp`

### Hiera data

- `modules/profile_haproxy/data/common.yaml`
- `modules/profile_haproxy/data/os/Debian.yaml`
- `modules/profile_haproxy/data/environment/production.yaml`
- `modules/profile_haproxy/data/environment/staging.yaml`
- `modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml`
- `modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml`

### Custom components

- `modules/profile_haproxy/lib/facter/haproxy_version.rb`
```

## Module Explanation

The module performs operations in the following order:

1. **`role::haproxy`** (`site/role/manifests/haproxy.pp`)
   - Evaluates the Linux-only condition `$facts['kernel'].downcase == 'linux'`.
   - Evaluates the role-specific `exec[None]`; its exact command and attributes require inspection of the original manifest.
   - Includes `::profile::base::base`.
   - Includes `::profile::loadbalancer::haproxy`.
   - Enforces `Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']`.
   - Uses `$facts['kernel']` to determine whether Linux-specific resources are evaluated.
   - The load-balancer profile chain evaluates `fact('environment')`.

2. **`profile::loadbalancer::haproxy`** (`site/profile/manifests/loadbalancer/haproxy.pp`)
   - Includes `profile_haproxy`.
   - Delegates installation, configuration, service management, and firewall configuration to `profile_haproxy`.

3. **`profile_haproxy`** (`modules/profile_haproxy/manifests/init.pp`)
   - Resolves the HAProxy parameters from Hiera.
   - Intended effective production values include:
     - `package_name`: `haproxy`
     - `config_dir`: `/etc/haproxy`
     - `config_file`: `/etc/haproxy/haproxy.cfg`
     - `service_name`: `haproxy`
     - `user`: `haproxy`
     - `group`: `haproxy`
     - `stats_enabled`: `true`
     - `stats_port`: `9001`
     - `stats_uri`: `/haproxy-stats`
     - `stats_user`: `admin`
     - `stats_password`: encrypted secret; encryption format requires source verification
     - `global_maxconn`: `32768`
     - `client_timeout`: `60s`
     - `server_timeout`: `60s`
     - `connect_timeout`: `5s`
     - `retries`: `3`
     - `ssl_enabled`: `true`
     - `ssl_cert_path`: `/etc/ssl/certs`
     - `ssl_key_path`: `/etc/ssl/private`
     - `ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`
     - `ssl_min_version`: `TLSv1.3`
     - `log_server`: `127.0.0.1`
     - `log_facility`: `local0`
     - `log_level`: `warning`
     - `backends`: intended to resolve to `webservers`, `api`, and `internal_monitoring`
   - Contains `profile_haproxy::install`.
   - Contains `profile_haproxy::config`.
   - Contains `profile_haproxy::service`.
   - Contains `profile_haproxy::firewall`.
   - Enforces `Class['profile_haproxy::install'] -> Class['profile_haproxy::config']`.
   - Notifies `Class['profile_haproxy::service']` when configuration changes.

4. **`profile_haproxy::install`** (`modules/profile_haproxy/manifests/install.pp`)
   - Installs package `haproxy` with ensure `present`.
   - Installs package `hatop` when `$extra_packages` is non-empty.
   - Creates group `haproxy`.
   - Creates user `haproxy`.
   - Creates `/etc/haproxy` as a directory.
   - Creates `/etc/haproxy/conf.d` as a directory.
   - Creates `/var/lib/haproxy` as a directory.
   - Preserves the ownership and modes defined in the Puppet manifest.
   - Debian data selects firewall provider `ufw`.
   - Debian data selects extra package `hatop`.

5. **`profile_haproxy::config`** (`modules/profile_haproxy/manifests/config.pp`)
   - Creates `/etc/haproxy/errors` before writing error files.
   - Renders `/etc/haproxy/haproxy.cfg` from `modules/profile_haproxy/templates/haproxy.cfg.erb`.
   - The main configuration renders:
     - `log 127.0.0.1 local0 warning`
     - `chroot /var/lib/haproxy`
     - `pidfile /var/run/haproxy.pid`
     - `maxconn 32768`
     - `user haproxy`
     - `group haproxy`
     - `daemon`
     - `stats socket /var/lib/haproxy/stats mode 660 level admin`
   - When TLS is enabled, renders:
     - `ssl-default-bind-ciphers ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`
     - `ssl-default-bind-options no-sslv3 no-tlsv10 no-tlsv11`
     - `tune.ssl.default-dh-param 2048`
   - Renders defaults:
     - `mode http`
     - `option httplog`
     - `option dontlognull`
     - `option forwardfor`
     - `option http-server-close`
     - `timeout connect 5s`
     - `timeout client 60s`
     - `timeout server 60s`
     - `retries 3`
     - `errorfile 503 /etc/haproxy/errors/503.http`
     - `errorfile 408 /etc/haproxy/errors/408.http`
   - When statistics are enabled, renders:
     - `listen stats`
     - `bind *:9001`
     - `stats enable`
     - `stats uri /haproxy-stats`
     - `stats realm HAProxy\ Statistics`
     - `stats auth admin:<encrypted-password>`
     - `stats admin if TRUE`
     - `stats refresh 30s`
   - Renders frontend `http_front`:
     - `bind *:80`
     - `bind *:443 ssl crt /etc/ssl/certs/haproxy.pem` when TLS is enabled
     - `http-request redirect scheme https unless { ssl_fc }`
     - `default_backend webservers`
   - Generates backend fragment references for:
     - `webservers` → `/etc/haproxy/conf.d/webservers.cfg`
     - `api` → `/etc/haproxy/conf.d/api.cfg`
     - `internal_monitoring` → `/etc/haproxy/conf.d/internal_monitoring.cfg`
   - Expands `$backends.each` into these three intended backend iterations:
     - **`webservers`**
       - Renders `/etc/haproxy/conf.d/webservers.cfg` from `modules/profile_haproxy/templates/backend.conf.epp`.
       - Emits `backend webservers`.
       - Emits `balance roundrobin`.
       - Emits `option httpchk GET /health`.
       - Emits `default-server inter 5s`.
       - Emits `server web1 10.0.1.10:8080 check weight 100`.
       - Emits `server web2 10.0.1.11:8080 check weight 100`.
       - Emits `server web3 10.0.1.12:8080 check weight 100`.
       - Adds `ssl verify none` to server lines when TLS is enabled.
     - **`api`**
       - Renders `/etc/haproxy/conf.d/api.cfg` from `modules/profile_haproxy/templates/backend.conf.epp`.
       - Emits `backend api`.
       - Emits `balance leastconn`.
       - Emits `option httpchk GET /api/health`.
       - Emits `default-server inter 10s`.
       - Emits `server api1-fra 10.100.2.10:3000 check weight 200`.
       - Emits `server api2-fra 10.100.2.11:3000 check weight 100`.
       - Adds `ssl verify none` to server lines when TLS is enabled.
     - **`internal_monitoring`**
       - Renders `/etc/haproxy/conf.d/internal_monitoring.cfg` from `modules/profile_haproxy/templates/backend.conf.epp`.
       - Emits `backend internal_monitoring`.
       - Emits `balance roundrobin`.
       - Emits `option httpchk GET /-/healthy`.
       - Emits `default-server inter 15s`.
       - Emits `server prom1-fra 10.100.3.10:9090 check weight 100`.
       - Adds `ssl verify none` to the server line when TLS is enabled.
   - Expands `['503', '408'].each` into:
     - `/etc/haproxy/errors/503.http`
     - `/etc/haproxy/errors/408.http`
   - Preserves Puppet-managed error-file contents; exact contents require source inspection.
   - When `stick_table_enabled` is true, creates `/etc/haproxy/conf.d/stick-tables.cfg`.
   - Intended production stick-table values are size `200k` and expiration `30m`; exact resource attributes and contents require source inspection.
   - Staging has `stick_table_enabled: false`, so the stick-table file is not intended to be created.

6. **`profile_haproxy::service`** (`modules/profile_haproxy/manifests/service.pp`)
   - Runs `exec['haproxy_config_check']` before activation or restart.
   - Uses `haproxy -c -f /etc/haproxy/haproxy.cfg`, or the exact command from the Puppet manifest if different.
   - Creates `/etc/systemd/system/haproxy.service.d`.
   - Creates `/etc/systemd/system/haproxy.service.d/override.conf`.
   - Runs `exec['haproxy_systemd_daemon_reload']` after the systemd drop-in changes.
   - Ensures service `haproxy` is running and enabled.
   - Creates `/etc/logrotate.d/haproxy`.
   - Ansible handlers must validate HAProxy configuration before restart.
   - Changes to `override.conf` must notify a systemd daemon reload.
   - Successful configuration changes must notify an HAProxy restart or reload.

7. **`profile_haproxy::firewall`** (`modules/profile_haproxy/manifests/firewall.pp`)
   - Evaluates `$firewall_provider == 'ufw'`.
   - Installs package `ufw`.
   - Allows TCP port `80`.
   - Allows TCP port `443`.
   - Enables UFW.
   - Preserves the Puppet manifest’s exact command flags and idempotence guards.

## Variables

**Variable Flow Summary**: 25 primary keys are listed in `common.yaml`, plus the separate `lookup_options` entry. Additional OS, environment, cluster, and node keys override or extend those defaults. The final values and hierarchy precedence require verification against the six Hiera source files. Backend data uses Puppet Hiera deep merge; Ansible must explicitly define nested-hash and server-list behavior.

### Variable Definitions

The following values are the values documented by the supplied migration plan. They must be verified against the source files before implementation.

#### `common.yaml` (defaults) → Migration note: Base defaults for all nodes

`modules/profile_haproxy/data/common.yaml`

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
- `profile_haproxy::stats_password`: encrypted value; encryption format requires source verification (type: secret/string)
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
- `profile_haproxy::backends`: hash containing `webservers` and `api` (type: hash)
- `lookup_options['profile_haproxy::backends']`: `deep` merge (type: hash)

#### `os/Debian.yaml` (OS-specific) → Migration note: Debian-specific package and firewall settings

`modules/profile_haproxy/data/os/Debian.yaml`

- `profile_haproxy::package_name`: `haproxy` (type: string)
- `profile_haproxy::config_dir`: `/etc/haproxy` (type: string)
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::extra_packages`: `[hatop]` (type: array)

#### `environment/production.yaml` (environment-specific) → Migration note: Production overrides

`modules/profile_haproxy/data/environment/production.yaml`

- `profile_haproxy::global_maxconn`: `16384` (type: integer)
- `profile_haproxy::ssl_enabled`: `true` (type: boolean)
- `profile_haproxy::log_level`: `warning` (type: string)
- `profile_haproxy::client_timeout`: `60s` (type: string)
- `profile_haproxy::server_timeout`: `60s` (type: string)
- `profile_haproxy::stats_enabled`: `false` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_size`: `200k` (type: string)
- `profile_haproxy::stick_table_expire`: `30m` (type: string)

#### `environment/staging.yaml` (environment-specific) → Migration note: Staging overrides

`modules/profile_haproxy/data/environment/staging.yaml`

- `profile_haproxy::global_maxconn`: `2048` (type: integer)
- `profile_haproxy::ssl_enabled`: `false` (type: boolean)
- `profile_haproxy::log_level`: `debug` (type: string)
- `profile_haproxy::stats_enabled`: `true` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `false` (type: boolean)

#### `cluster/haproxy_prod_fra.yaml` (cluster-specific) → Migration note: Frankfurt production overrides

`modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml`

- `profile_haproxy::global_maxconn`: `32768` (type: integer)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (type: string)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (type: string)
- `profile_haproxy::backends`: hash adding `internal_monitoring` and overriding nested `api` data through deep merge (type: hash)

#### `nodes/lb01.fra.example.com.yaml` (host-specific) → Migration note: Node-specific statistics and backend overrides

`modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml`

- `profile_haproxy::stats_enabled`: `true` (type: boolean)
- `profile_haproxy::stats_port`: `9001` (type: integer)
- `profile_haproxy::backends`: hash overriding the `api.servers` list (type: hash)

### Variable Migration Summary

- **Common defaults**: 25 primary Hiera keys in `common.yaml`, plus one `lookup_options` entry.
- **OS-specific variables**: 4 keys in `os/Debian.yaml`.
- **Environment-specific variables**: 9 production keys and 5 staging keys.
- **Cluster-specific variables**: 4 keys in `cluster/haproxy_prod_fra.yaml`.
- **Host-specific variables**: 3 keys in `nodes/lb01.fra.example.com.yaml`.
- **Encrypted variables**: 1 documented direct HAProxy secret, `profile_haproxy::stats_password`; encryption format requires verification.
- **Deep-merged variables**: `profile_haproxy::backends`.
- **List merge requiring an explicit policy**: nested backend `servers` arrays.

### Hiera-to-Ansible Mapping

Use `haproxy_backends` as the single Ansible name mapped from `profile_haproxy::backends`.

```yaml
haproxy_package_name: haproxy
haproxy_config_dir: /etc/haproxy
haproxy_config_file: /etc/haproxy/haproxy.cfg
haproxy_service_name: haproxy
haproxy_user: haproxy
haproxy_group: haproxy

haproxy_stats_enabled: true
haproxy_stats_port: 9001
haproxy_stats_uri: /haproxy-stats
haproxy_stats_user: admin
haproxy_stats_password: "{{ vault_haproxy_stats_password }}"

haproxy_global_maxconn: 32768
haproxy_client_timeout: 60s
haproxy_server_timeout: 60s
haproxy_connect_timeout: 5s
haproxy_retries: 3

haproxy_ssl_enabled: true
haproxy_ssl_cert_path: /etc/ssl/certs
haproxy_ssl_key_path: /etc/ssl/private
haproxy_ssl_ciphers: "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384"
haproxy_ssl_min_version: TLSv1.3

haproxy_log_server: 127.0.0.1
haproxy_log_facility: local0
haproxy_log_level: warning

haproxy_extra_packages:
  - hatop

haproxy_stick_table_enabled: true
haproxy_stick_table_size: 200k
haproxy_stick_table_expire: 30m

haproxy_backends:
  webservers:
    balance: roundrobin
    port: 8080
    health_check: "httpchk GET /health"
    health_interval: 5s
    servers:
      - name: web1
        address: 10.0.1.10
        port: 8080
        weight: 100
      - name: web2
        address: 10.0.1.11
        port: 8080
        weight: 100
      - name: web3
        address: 10.0.1.12
        port: 8080
        weight: 100
  api:
    balance: leastconn
    port: 3000
    health_check: "httpchk GET /api/health"
    health_interval: 10s
    servers:
      - name: api1-fra
        address: 10.100.2.10
        port: 3000
        weight: 200
      - name: api2-fra
        address: 10.100.2.11
        port: 3000
        weight: 100
  internal_monitoring:
    balance: roundrobin
    port: 9090
    health_check: "httpchk GET /-/healthy"
    health_interval: 15s
    servers:
      - name: prom1-fra
        address: 10.100.3.10
        port: 9090
        weight: 100
```

- Nested hashes must use recursive combination equivalent to `combine(recursive=true)`.
- The `api.servers` list must use an explicit replacement policy for the node-level override unless source analysis confirms list merging is required.
- Do not expose `haproxy_stats_password` in logs, command arguments, debug output, or rendered check output.

### Cross-Level Overrides

- **`profile_haproxy::package_name`**
  - Defined in common and Debian data.
  - Effective value: `haproxy`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::config_dir`**
  - Defined in common and Debian data.
  - Effective value: `/etc/haproxy`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::global_maxconn`**
  - Common: `4096`
  - Production: `16384`
  - Frankfurt cluster: `32768`
  - Effective documented value: `32768`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::stats_enabled`**
  - Common: `true`
  - Production: `false`
  - `lb01.fra.example.com`: `true`
  - Effective documented value: `true`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::stats_port`**
  - Common: `9000`
  - `lb01.fra.example.com`: `9001`
  - Effective documented value: `9001`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::ssl_enabled`**
  - Common: `false`
  - Production: `true`
  - Effective documented value: `true`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::log_level`**
  - Common: `info`
  - Production: `warning`
  - Effective documented value: `warning`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::client_timeout`**
  - Common: `30s`
  - Production: `60s`
  - Effective documented value: `60s`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::server_timeout`**
  - Common: `30s`
  - Production: `60s`
  - Effective documented value: `60s`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::ssl_ciphers`**
  - Common: AES128 cipher set
  - Frankfurt cluster: AES256 cipher set
  - Effective documented value: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::ssl_min_version`**
  - Common: `TLSv1.2`
  - Frankfurt cluster: `TLSv1.3`
  - Effective documented value: `TLSv1.3`.
  - Merge strategy: first value according to Hiera precedence.

- **`profile_haproxy::backends`**
  - Common: `webservers` and `api`
  - Cluster: adds `internal_monitoring`
  - Node: overrides the `api.servers` list
  - Merge strategy: Puppet Hiera `deep` for nested hashes.
  - Ansible policy: recursive hash merge with explicit replacement of the node-level `api.servers` list.

### Merge Strategy Notes

- Variables using `hash` merge have values merged shallowly.
- Variables using `deep` merge have nested hashes recursively merged.
- Variables using `first`, the default strategy, use the first value found according to Hiera precedence.
- Backend server lists are not assumed to merge automatically. The Ansible migration must explicitly replace or merge the list.

## Custom Types and Providers

### Custom fact: `haproxy_version`

- File: `modules/profile_haproxy/lib/facter/haproxy_version.rb`
- Scope: Linux only.
- Intended command: `haproxy -v 2>/dev/null`
- Intended parsing: semantic versions matching `version\s+(\d+\.\d+\.\d+)`.
- Intended return value:
  - Semantic version string when detected.
  - `nil` when HAProxy is unavailable or output does not match.
- These implementation details require independent source inspection because the supplied validation summary did not include the file contents.
- Ansible equivalent:
  - Run `haproxy -v` with `changed_when: false`.
  - Parse registered output with a regular expression.
  - Alternatively install a custom fact under `/etc/ansible/facts.d/`.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

The supplied execution tree does not show HAProxy resources from the Redis, VCS repository, or APT modules. Do not migrate those dependencies unless other control-repo code uses them.

**System package dependencies**:

- `haproxy`
- `hatop`
- `ufw`

**Service dependencies**:

- `::profile::base::base` before `::profile::loadbalancer::haproxy`
- Installation before configuration
- Configuration before service activation or restart
- Systemd daemon reload after `override.conf` changes
- HAProxy configuration validation before starting or restarting `haproxy`

## Puppet Facts Used

- `$facts['kernel']`
  - Provides the operating-system kernel name.
  - Used to restrict Linux-specific resources to Linux systems.

- `fact('environment')`
  - Provides the Puppet environment.
  - Evaluated in the load-balancer profile chain.

- `haproxy_version`
  - Intended to provide the installed HAProxy semantic version.
  - Generated from `haproxy -v`.
  - The custom fact implementation requires independent source verification.

## Template Conversion Notes

### `modules/profile_haproxy/templates/haproxy.cfg.erb`

- Destination: `/etc/haproxy/haproxy.cfg`
- Expected render count: `1`; verify against resolved data.
- Jinja2 variables:
  - `log_server` → HAProxy global `log` server address
  - `log_facility` → HAProxy global `log` facility
  - `log_level` → HAProxy global `log` level
  - `global_maxconn` → `maxconn`
  - `user` → global HAProxy user
  - `group` → global HAProxy group
  - `ssl_enabled` → controls TLS-specific global and frontend output
  - `ssl_ciphers` → `ssl-default-bind-ciphers`
  - `ssl_min_version` → TLS minimum-version behavior; exact emitted syntax requires template verification
  - `ssl_cert_path` → TLS certificate path and frontend certificate binding
  - `ssl_key_path` → private-key path or certificate/key lookup behavior; exact emitted syntax requires template verification
  - `connect_timeout` → `timeout connect`
  - `client_timeout` → `timeout client`
  - `server_timeout` → `timeout server`
  - `retries` → default retries
  - `stats_enabled` → controls the statistics listener
  - `stats_port` → statistics listener bind port
  - `stats_uri` → statistics URI
  - `stats_user` → statistics authentication username
  - `stats_password` → statistics authentication password; use Ansible Vault or an external secret manager
  - `backends` → emits effective backend references or fragment references
- Five logic blocks to preserve:
  1. Conditional TLS global settings.
  2. Conditional TLS frontend binding and HTTPS redirect behavior.
  3. Conditional statistics listener.
  4. Iteration over effective backends to emit backend fragment references.
  5. Conditional/default rendering of TLS certificate/key and minimum-version-related settings; exact expression must be confirmed from the ERB source.
- Preserve exact HAProxy syntax.
- Use `no_log: true` for tasks that handle the statistics password where practical.
- Do not expose decrypted credentials in command arguments, logs, or debug output.

### `modules/profile_haproxy/templates/backend.conf.epp`

- Destination pattern: `/etc/haproxy/conf.d/<backend_name>.cfg`
- Expected render counts:
  - `webservers`: `1`
  - `api`: `1`
  - `internal_monitoring`: `1`
  - Final counts require resolved Hiera verification.
- Variables:
  - `backend_name`
  - `balance`
  - `port`
  - `servers`
  - `health_check`
  - `health_interval`
  - `ssl_enabled`
- Logic:
  - Conditionally emits the HTTP health-check option.
  - Conditionally emits the health-check interval.
  - Iterates over backend server definitions.
  - Conditionally appends `ssl verify none` to server lines.
- Ansible conversion:
  - Iterate over `haproxy_backends | dict2items`.
  - Render one fragment per backend.
  - Use a nested loop for each backend’s `servers`.
  - Explicitly define replacement or merge behavior for node-level server lists.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/haproxy.pp`
- `site/profile/manifests/loadbalancer/haproxy.pp`
- `modules/profile_haproxy/manifests/init.pp`
- `modules/profile_haproxy/manifests/install.pp`
- `modules/profile_haproxy/manifests/config.pp`
- `modules/profile_haproxy/manifests/service.pp`
- `modules/profile_haproxy/manifests/firewall.pp`
- `modules/profile_haproxy/templates/haproxy.cfg.erb`
- `modules/profile_haproxy/templates/backend.conf.epp`
- `modules/profile_haproxy/data/common.yaml`
- `modules/profile_haproxy/data/os/Debian.yaml`
- `modules/profile_haproxy/data/environment/production.yaml`
- `modules/profile_haproxy/data/environment/staging.yaml`
- `modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml`
- `modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml`
- `modules/profile_haproxy/lib/facter/haproxy_version.rb`
- `/etc/haproxy/haproxy.cfg`
- `/etc/haproxy/conf.d/webservers.cfg`
- `/etc/haproxy/conf.d/api.cfg`
- `/etc/haproxy/conf.d/internal_monitoring.cfg`
- `/etc/haproxy/conf.d/stick-tables.cfg`
- `/etc/haproxy/errors/503.http`
- `/etc/haproxy/errors/408.http