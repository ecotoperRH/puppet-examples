---
source-path: modules/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module installs and configures HAProxy as a Linux load balancer, creates its service account and runtime directories, renders the main configuration and three backend fragments, installs custom error pages, manages the HAProxy service and log rotation, and configures UFW or firewalld. The source plan reports an effective `haproxy_prod_fra` configuration with maximum connections of `32768`, TLS 1.3 settings, and the `webservers`, `api`, and `internal_monitoring` backends; these Hiera-derived values require verification against the referenced data files. HAProxy statistics use an encrypted Hiera eyaml password that must migrate to Ansible Vault or an external secret provider. PuppetDB-exported resources and collectors must be replaced with explicit Ansible inventory, service discovery, or dynamic inventory data.

## Service Type and Instances

**Service Type**: Linux load balancer / reverse proxy

**Configured Instances**:

- **haproxy**: Main HAProxy service and load-balancing process
  - Package: `haproxy`
  - Service: `haproxy`
  - Configuration: `/etc/haproxy/haproxy.cfg`
  - Configuration directory: `/etc/haproxy`
  - Backend fragments: `/etc/haproxy/conf.d/*.cfg`
  - Error pages: `/etc/haproxy/errors/503.http`, `/etc/haproxy/errors/408.http`
  - Runtime directory: `/var/lib/haproxy`
  - User: `haproxy`
  - Group: `haproxy`
  - Statistics port: `9000`
  - Statistics URI: `/haproxy-stats`
  - Statistics user: `admin`
  - Statistics password: encrypted Hiera eyaml value; migrate to Ansible Vault or an external secret provider
  - HTTP listener ports: `80/tcp`, `443/tcp`
  - Effective maximum connections reported by the source plan: `32768`; verify from Hiera
  - Client timeout: `30s`
  - Server timeout: `30s`
  - Connect timeout: `5s`
  - Retries: `3`
  - SSL enabled: `false`
  - Effective SSL ciphers reported by the source plan: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384`; verify from Hiera
  - Effective minimum TLS version reported by the source plan: `TLSv1.3`; verify from Hiera
  - Log server: `127.0.0.1`
  - Log facility: `local0`
  - Log level: `info`

- **webservers**: Static web application backend
  - Balance method: `roundrobin`
  - Port: `8080`
  - Health check: `httpchk GET /health`
  - Health interval: `5s`
  - Servers:
    - `web1`: `10.0.1.10`, weight `100`
    - `web2`: `10.0.1.11`, weight `100`
    - `web3`: `10.0.1.12`, weight `100`

- **api**: Static API backend
  - Balance method: `leastconn`
  - Port: `3000`
  - Health check: `httpchk GET /api/health`
  - Health interval: `10s`
  - Servers:
    - `api1`: `10.0.2.10`, weight `100`
    - `api2`: `10.0.2.11`, weight `100`

- **internal_monitoring**: Internal monitoring backend
  - Balance method: `roundrobin`
  - Port: `9090`
  - Health check: `httpchk GET /-/healthy`
  - Health interval: `15s`
  - Servers:
    - `prom1-fra`: `10.100.3.10`, weight `100`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
site/role/manifests/haproxy.pp
site/profile/manifests/loadbalancer/haproxy.pp

site/modules/linux/profile_haproxy/manifests/init.pp
site/modules/linux/profile_haproxy/manifests/install.pp
site/modules/linux/profile_haproxy/manifests/config.pp
site/modules/linux/profile_haproxy/manifests/discover.pp
site/modules/linux/profile_haproxy/manifests/service.pp
site/modules/linux/profile_haproxy/manifests/firewall.pp

site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb
site/modules/linux/profile_haproxy/templates/backend.conf.epp

site/modules/linux/profile_haproxy/files/haproxy_errors/503.http
site/modules/linux/profile_haproxy/files/haproxy_errors/408.http

site/modules/linux/profile_haproxy/data/common.yaml
site/modules/linux/profile_haproxy/data/cluster/haproxy_prod_fra.yaml

site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb
```

## Module Explanation

The module performs operations in this order:

1. **`role::haproxy`** (`site/role/manifests/haproxy.pp`):
   - Executes conditionally when `$facts['kernel'].downcase == 'linux'`.
   - Includes `::profile::base::base`.
   - Includes `::profile::loadbalancer::haproxy`.
   - The Linux branch contains `Exec[None]`; no command or attributes were supplied.
   - Execution order is `Class['::profile::base::base'] -> Class['::profile::loadbalancer::haproxy']`.
   - The `environment` fact is not attributed to this role; it is referenced by the load balancer profile.

2. **`::profile::loadbalancer::haproxy`** (`site/profile/manifests/loadbalancer/haproxy.pp`):
   - Includes `profile_haproxy`.
   - References the Puppet `environment` fact.
   - Provides no additional resources in the supplied execution tree.

3. **`profile_haproxy`** (`site/modules/linux/profile_haproxy/manifests/init.pp`):
   - Contains `profile_haproxy::install`.
   - Contains `profile_haproxy::config`.
   - Contains `profile_haproxy::discover`.
   - Contains `profile_haproxy::service`.
   - Contains `profile_haproxy::firewall`.
   - Orders installation before configuration.
   - Orders configuration before discovery.
   - The discovery class notifies the service.
   - Configuration and backend fragment changes notify the service.

4. **`profile_haproxy::install`** (`site/modules/linux/profile_haproxy/manifests/install.pp`):
   - Installs `package['haproxy']` with `ensure => installed`.
   - Looks up `profile_haproxy::extra_packages` as `Array[String]` with first-value lookup and default `[]`.
   - The extra package loop runs zero times with the supplied default; no additional package resources are created.
   - Creates `group['haproxy']` with `ensure => present` and `system => true`.
   - Creates `user['haproxy']` with:
     - `gid => haproxy`
     - `home => /var/lib/haproxy`
     - `shell => /sbin/nologin`
     - `system => true`
     - Requirement on `Group['haproxy']`
   - Creates `/etc/haproxy` as a `0755` directory owned by `root:haproxy`.
   - Creates `/etc/haproxy/conf.d` as a `0755` directory owned by `root:haproxy`.
   - Creates `/var/lib/haproxy` as a `0750` directory owned by `haproxy:haproxy`.
   - Looks up `profile_haproxy::selinux_enabled` as a Boolean with first-value lookup and default `false`.
   - The SELinux branch is inactive with the supplied default.
   - When enabled, runs `exec['haproxy_selinux_connect']` with:
     - Command: `setsebool -P haproxy_connect_any 1`
     - Unless condition: `getsebool haproxy_connect_any | grep -q on`
     - Search path: `/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`
     - Requirement on `Package['haproxy']`

5. **`profile_haproxy::config`** (`site/modules/linux/profile_haproxy/manifests/config.pp`):
   - Renders `/etc/haproxy/haproxy.cfg` from `site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb`.
   - Sets owner `root`, group `haproxy`, and mode `0640`.
   - Notifies `Class['profile_haproxy::service']`.
   - The source plan reports that `$backends.each` runs three times after deep merging common and cluster data. The evaluated Hiera data must be verified against the referenced files.
   - Backend iteration `webservers`:
     - Renders `/etc/haproxy/conf.d/webservers.cfg`.
     - Uses `roundrobin`, port `8080`, health check `httpchk GET /health`, interval `5s`, and servers `web1`, `web2`, and `web3`.
     - Passes `ssl_enabled=false` to `backend.conf.epp`.
     - Sets owner `root`, group `haproxy`, mode `0640`.
     - Notifies `Class['profile_haproxy::service']`.
   - Backend iteration `api`:
     - Renders `/etc/haproxy/conf.d/api.cfg`.
     - Uses `leastconn`, port `3000`, health check `httpchk GET /api/health`, interval `10s`, and servers `api1` and `api2`.
     - Passes `ssl_enabled=false` to `backend.conf.epp`.
     - Sets owner `root`, group `haproxy`, mode `0640`.
     - Notifies `Class['profile_haproxy::service']`.
   - Backend iteration `internal_monitoring`:
     - Renders `/etc/haproxy/conf.d/internal_monitoring.cfg`.
     - Uses `roundrobin`, port `9090`, health check `httpchk GET /-/healthy`, interval `15s`, and server `prom1-fra`.
     - Passes `ssl_enabled=false` to `backend.conf.epp`.
     - Sets owner `root`, group `haproxy`, mode `0640`.
     - Notifies `Class['profile_haproxy::service']`.
   - Error-page iteration `503`:
     - Installs `/etc/haproxy/errors/503.http`.
     - Source: `puppet:///modules/profile_haproxy/haproxy_errors/503.http`
     - Owner `root`, group `haproxy`, mode `0644`.
   - Error-page iteration `408`:
     - Installs `/etc/haproxy/errors/408.http`.
     - Source: `puppet:///modules/profile_haproxy/haproxy_errors/408.http`
     - Owner `root`, group `haproxy`, mode `0644`.
   - Creates `/etc/haproxy/errors` as a `0755` directory owned by `root:haproxy`.
   - Orders the error directory before `/etc/haproxy/errors/503.http`.
   - Looks up `profile_haproxy::stick_table_enabled` as a Boolean with first-value lookup and default `false`.
   - The stick-table branch is inactive with the supplied default.
   - When enabled, creates `/etc/haproxy/conf.d/stick-tables.cfg` with mode `0640`, owner `root`, group `haproxy`, and content based on:
     ```text
     # Managed by Puppet
     stick-table type ip size ${stick_table_size} expire ${stick_table_expire}
     ```
   - Stick-table configuration notifies `Class['profile_haproxy::service']`.

6. **`profile_haproxy::discover`** (`site/modules/linux/profile_haproxy/manifests/discover.pp`):
   - Exports `@@haproxy::balancermember[$facts['networking']['fqdn']]`.
   - Exports a local `webservers` member using the local FQDN, local IP, port `8080`, and option `check`.
   - Collects `Haproxy::Balancermember` resources where `listening_service == 'webservers'`.
   - Executes a PuppetDB query for `Profile::App_server` resources whose `Profile::Base` environment matches the local `puppet_environment`.
   - The dynamic application-server loop runs once per returned PuppetDB result; concrete server names cannot be expanded from the supplied data.
   - For each returned result:
     - Uses the returned `certname` as the server name and address.
     - Uses `$server['parameters']['port']` as the application port.
     - Creates `haproxy::balancermember["api-${certname}"]`.
     - Sets `listening_service => api`.
     - Sets `options => check inter 10s`.
   - Ansible must replace this behavior with `haproxy_api_servers`, service discovery, or a dynamic inventory plugin.

7. **`profile_haproxy::service`** (`site/modules/linux/profile_haproxy/manifests/service.pp`):
   - Manages `service['haproxy']` with:
     - `ensure => running`
     - `enable => true`
     - `hasrestart => true`
     - `hasstatus => true`
   - Requires `Package['haproxy']`.
   - Subscribes to `/etc/haproxy/haproxy.cfg`.
   - Runs `exec['haproxy_config_check']` with:
     - Command: `haproxy -c -f /etc/haproxy/haproxy.cfg`
     - Search path: `/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`
     - `refreshonly => true`
   - The configuration check subscribes to `/etc/haproxy/haproxy.cfg` and runs before `Service['haproxy']`.
   - Creates `/etc/logrotate.d/haproxy` with owner `root`, group `root`, and mode `0644`.
   - Log rotation is daily, retains 14 rotations, compresses old logs, and sends `HUP` to the HAProxy PID after rotation.

8. **`profile_haproxy::firewall`** (`site/modules/linux/profile_haproxy/manifests/firewall.pp`):
   - Looks up `profile_haproxy::firewall_provider` as a string with first-value lookup and default `ufw`.
   - Normalizes statistics port `9000` through `base_utils::normalize_port(9000)`, producing integer `9000`.
   - Effective provider is UFW.
   - UFW branch:
     - Installs `package['ufw']`.
     - Runs `exec['ufw_allow_http']` for `80/tcp`.
     - Runs `exec['ufw_allow_https']` for `443/tcp`.
     - Runs `exec['ufw_enable']` with `ufw --force enable`.
     - No `ufw_allow_stats` resource is asserted because it is absent from the validated structured execution tree.
   - Firewalld branch:
     - The validated structured tree shows `exec['firewalld_reload']` only.
     - No firewalld port-rule resources are asserted for ports `80`, `443`, or `9000`.
     - If selected, the reload command is `firewall-cmd --reload` and is refresh-only.
   - Unsupported providers produce `notify['Unknown firewall provider: ${firewall_provider}']`.

## Variables

**Variable Flow Summary**: 24 primary variables are listed in `common.yaml`, with cluster-level overrides and additions reported in `cluster/haproxy_prod_fra.yaml`. The source plan reports four effective override areas: maximum connections, SSL ciphers, minimum TLS version, and the deep-merged backend map. Hiera values and merge results require verification against the referenced data files because they were not present in the supplied structured execution summary.

### Variable Definitions

#### `common.yaml` (defaults) → Migration note: Base defaults for all nodes; values below are reported by the source plan and require verification

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
- `profile_haproxy::stats_password`: `[ENCRYPTED Hiera eyaml value]` (type: encrypted string)
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
- `lookup_options.profile_haproxy::backends.merge`: `deep` (type: string)

#### `cluster/haproxy_prod_fra.yaml` → Migration note: Cluster-specific overrides and additions; values below require verification

- `profile_haproxy::global_maxconn`: `32768` (type: integer)
- `profile_haproxy::ssl_ciphers`: `ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384` (type: string)
- `profile_haproxy::ssl_min_version`: `TLSv1.3` (type: string)
- `profile_haproxy::backends.internal_monitoring.balance`: `roundrobin` (type: string)
- `profile_haproxy::backends.internal_monitoring.port`: `9090` (type: integer)
- `profile_haproxy::backends.internal_monitoring.health_check`: `httpchk GET /-/healthy` (type: string)
- `profile_haproxy::backends.internal_monitoring.health_interval`: `15s` (type: string)
- `profile_haproxy::backends.internal_monitoring.servers[0].name`: `prom1-fra` (type: string)
- `profile_haproxy::backends.internal_monitoring.servers[0].address`: `10.100.3.10` (type: string)
- `profile_haproxy::backends.internal_monitoring.servers[0].weight`: `100` (type: integer)

#### Implicit/default lookup variables → Migration note: First-lookup or conditional controls

- `profile_haproxy::extra_packages`: `[]` (type: array of strings)
- `profile_haproxy::selinux_enabled`: `false` (type: boolean)
- `profile_haproxy::stick_table_enabled`: `false` (type: boolean)
- `profile_haproxy::firewall_provider`: `ufw` (type: string)
- `profile_haproxy::firewall_zone`: `public` when firewalld is selected (type: string)

#### Effective Ansible variable mapping

- `haproxy_package_name`: `haproxy`
- `haproxy_config_dir`: `/etc/haproxy`
- `haproxy_config_file`: `/etc/haproxy/haproxy.cfg`
- `haproxy_service_name`: `haproxy`
- `haproxy_user`: `haproxy`
- `haproxy_group`: `haproxy`
- `haproxy_stats_enabled`: `true`
- `haproxy_stats_port`: `9000`
- `haproxy_stats_uri`: `/haproxy-stats`
- `haproxy_stats_user`: `admin`
- `haproxy_stats_password`: Ansible Vault or external secret lookup
- `haproxy_global_maxconn`: `32768` as reported; verify from Hiera
- `haproxy_client_timeout`: `30s`
- `haproxy_server_timeout`: `30s`
- `haproxy_connect_timeout`: `5s`
- `haproxy_retries`: `3`
- `haproxy_ssl_enabled`: `false`
- `haproxy_ssl_cert_path`: `/etc/ssl/certs`
- `haproxy_ssl_key_path`: `/etc/ssl/private`
- `haproxy_ssl_ciphers`: AES256 cipher suite as reported; verify from Hiera
- `haproxy_ssl_min_version`: `TLSv1.3` as reported; verify from Hiera
- `haproxy_log_server`: `127.0.0.1`
- `haproxy_log_facility`: `local0`
- `haproxy_log_level`: `info`
- `haproxy_backends`: effective map reported as `webservers`, `api`, and `internal_monitoring`; verify from Hiera

### Variable Migration Summary

- **Common defaults**: 24 primary variables from `common.yaml`
- **Cluster-specific variables**: 3 scalar overrides plus the `internal_monitoring` deep-merge addition
- **Effective backend instances**: 3 reported instances; verify the evaluated backend map
- **OS-specific variables**: 0 supplied
- **Environment-specific variables**: 0 supplied beyond cluster data
- **Host-specific variables**: 0 supplied
- **Encrypted variables**: 1 concrete HAProxy statistics credential
- **PuppetDB-derived values**: Dynamic API application-server names, addresses, and ports
- **Sensitive file references**: `/etc/ssl/certs` and `/etc/ssl/private`

### Cross-Level Overrides

- `profile_haproxy::global_maxconn`: common `4096`, cluster `32768`; merge strategy: first/highest-priority override; reported effective value: `32768`
- `profile_haproxy::ssl_ciphers`: common AES128 cipher suite, cluster AES256 cipher suite; merge strategy: first/highest-priority override; reported effective value: AES256 cipher suite
- `profile_haproxy::ssl_min_version`: common `TLSv1.2`, cluster `TLSv1.3`; merge strategy: first/highest-priority override; reported effective value: `TLSv1.3`
- `profile_haproxy::backends`: common `webservers` and `api`, cluster `internal_monitoring`; merge strategy: `deep`; reported effective map contains all three backends

### Merge Strategy Notes

- Variables using `hash` merge combine hash values from multiple levels using shallow merging.
- Variables using `deep` merge recursively combine nested hash values.
- Variables using `first` use the first value found according to Hiera hierarchy.
- Scalar overrides use first/highest-priority lookup behavior.
- The backend deep-merge result must be confirmed from `common.yaml` and `cluster/haproxy_prod_fra.yaml`.

## Custom Types and Providers

### Custom Facter fact

- **Fact**: `haproxy_version`
- **File**: `site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb`
- **Reported behavior**: Linux-confined fact executing `haproxy -v 2>/dev/null`, extracting the first semantic version after `version`, and returning `nil` when unavailable or unmatched.
- **Validation status**: The fact file is listed in supplementary module content, but the supplied structured execution tree does not include a custom-fact entry. Verify the implementation before migration.
- **Ansible equivalent**:
  - Run `haproxy -v` with `ansible.builtin.command`.
  - Register the result.
  - Parse the version with a Jinja regular expression.
  - Create a custom Ansible fact only if required.

### Cross-module function

- `base_utils::normalize_port(9000)` is used by `profile_haproxy::firewall`.
- Reported normalized value: integer `9000`.
- Implement as an Ansible variable cast or validation task.

## Dependencies

**External module dependencies**: The source plan reports the following supplementary metadata dependencies; direct use is not represented in the supplied execution tree:

- `puppetlabs-stdlib` `9.7.0`
- `puppetlabs-concat` `9.0.2`
- `puppetlabs-firewall` `8.1.3`
- `puppetlabs-vcsrepo` `6.1.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

Only the HAProxy profile's firewall logic is visible in the supplied execution path. Redis, APT, VCS repository, and concat dependencies are not directly instantiated by the shown profile.

**System package dependencies**:

- `haproxy`
- `ufw` when `firewall_provider=ufw`
- No extra packages with `extra_packages=[]`

**Service dependencies**:

- `Package['haproxy']` before `Service['haproxy']`
- Installation before configuration
- Configuration before discovery
- Discovery notifies the HAProxy service
- Configuration validation runs before the HAProxy service
- Main configuration changes trigger validation and service refresh
- Backend fragment changes notify the HAProxy service

## Puppet Facts Used

- `$facts['kernel']`
  - Determines whether `role::haproxy` executes on Linux.
- `$facts['networking']['fqdn']`
  - Used as the exported balancer-member title and server name.
- `$facts['networking']['ip']`
  - Used as the exported balancer-member IP address.
- `$facts['puppet_environment']`
  - Restricts the PuppetDB query to application servers in the same environment.
- `fact('environment')`
  - Referenced by `site/profile/manifests/loadbalancer/haproxy.pp`.
- `haproxy_version`
  - Reported custom Linux fact for the installed HAProxy version; verify because it is not present in the supplied structured execution tree.

## Template Conversion Notes

### `site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb`

- Render count: `1` as reported; verify with evaluated Hiera data.
- Destination: `/etc/haproxy/haproxy.cfg`
- Owner: `root`
- Group: `haproxy`
- Mode: `0640`
- Reported complexity: 21 variables and 4 logic blocks.
- Variables include statistics settings, encrypted statistics password, connection limits, timeouts, retries, TLS paths and settings, logging values, and backend configuration.
- Convert statistics, TLS, logging, and backend/configuration logic blocks to Jinja conditionals.
- Store the statistics password in Ansible Vault or an external secret provider.
- Use `no_log: true` for secret-handling tasks.
- Do not log the rendered statistics password.
- Preserve restrictive configuration ownership and permissions.

### `site/modules/linux/profile_haproxy/templates/backend.conf.epp`

- Reported render count: `3`; verify with evaluated Hiera data.
- Destinations:
  - `/etc/haproxy/conf.d/webservers.cfg`
  - `/etc/haproxy/conf.d/api.cfg`
  - `/etc/haproxy/conf.d/internal_monitoring.cfg`
- Owner: `root`
- Group: `haproxy`
- Mode: `0640`
- Reported complexity: 11 variables and 6 logic blocks.
- Variables include `backend_name`, `balance`, `port`, `servers`, `health_check`, `health_interval`, and `ssl_enabled`.
- Server fields include `name`, `address`, and `weight`.
- Convert the EPP server iteration to a Jinja loop.
- Preserve conditional rendering for health checks, health intervals, and SSL-specific server options.

### Static error files

- `site/modules/linux/profile_haproxy/files/haproxy_errors/503.http`
  - Copy count: `1` as reported
  - Destination: `/etc/haproxy/errors/503.http`
  - Owner: `root`
  - Group: `haproxy`
  - Mode: `0644`
- `site/modules/linux/profile_haproxy/files/haproxy_errors/408.http`
  - Copy count: `1` as reported
  - Destination: `/etc/haproxy/errors/408.http`
  - Owner: `root`
  - Group: `haproxy`
  - Mode: `0644`
- Static-file paths and copy behavior are documented in supplementary plan content and should be verified against the source files.

## PuppetDB Dependencies

**Context**: PuppetDB provides cross-node resource sharing, node facts, and infrastructure queries. This module uses exported balancer members, resource collection, and a PuppetDB class-resource query.

### Exported Resources

- Resource: `@@haproxy::balancermember[$facts['networking']['fqdn']]`
- Exported data:
  - `listening_service`: `webservers`
  - `server_names`: local system FQDN
  - `ipaddresses`: local system IP
  - `ports`: `8080`
  - `options`: `check`
- Migration notes:
  - Replace exported resources with explicit Ansible inventory or group variables.
  - Preserve the server name, address, port, and health-check options in the inventory model.

### Resource Collectors

- Collector: `Haproxy::Balancermember <| listening_service == 'webservers' |>`.
- Collects all exported balancer members for the `webservers` service.
- Migration notes:
  - Replace the collector with an inventory group such as `haproxy_webservers`.
  - Ensure all expected web servers are present in inventory before rendering HAProxy configuration.

### PuppetDB Queries

- Query:
  ```text
  resources[certname, parameters] {
    type = 'Class' and title = 'Profile::App_server'
    and certname in resources[certname] {
      type = 'Class' and title = 'Profile::Base'
      and parameters.environment = '${facts['puppet_environment']}'
    }
  }
  ```
- Returned data:
  - Application-server `certname`
  - Application-server class parameters, including the application port
- Migration notes:
  - The supplied data does not identify concrete query results.
  - Replace the query with `haproxy_api_servers`, service discovery, or an Ansible dynamic inventory plugin.
  - Preserve the returned application port and the `check inter 10s` option.

### Host Identity Data

- `$facts['networking']['fqdn']` identifies the local exported webserver.
- `$facts['networking']['ip']` supplies the local exported webserver address.
- `$facts['puppet_environment']` scopes API-server discovery to the local Puppet environment.
- Ansible must obtain equivalent identity and environment data from inventory, host variables, or the service-discovery source.

## Credentials and Sensitive Data

- `profile_haproxy::stats_password`
  - Source: `site/modules/linux/profile_haproxy/data/common.yaml`
  - Current storage: Hiera eyaml encrypted value, reported as `ENC[PKCS7,...]`
  - Usage: HAProxy statistics authentication
  - Migration: Store as `haproxy_stats_password` in Ansible Vault or an external secret provider.
  - Handling: Use `no_log: true`; do not print the value or rendered configuration.
- `profile_haproxy::ssl_cert_path`
  - Value: `/etc/ssl/certs`
  - Certificate material must come from Vault or another protected certificate source.
- `profile_haproxy::ssl_key_path`
  - Value: `/etc/ssl/private`
  - Private keys require restricted ownership and mode `0600`.
- Redis credentials and TLS paths reported in dependency metadata are not instantiated by this HAProxy execution tree.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/haproxy.pp`
- `site/profile/manifests/loadbalancer/haproxy.pp`
- `site/modules/linux/profile_haproxy/manifests/init.pp`
- `site/modules/linux/profile_haproxy/manifests/install.pp`
- `site/modules/linux/profile_haproxy/manifests/config.pp`
- `site/modules/linux/profile_haproxy/manifests/discover.pp`
- `site/modules/linux/profile_haproxy/manifests/service.pp`
- `site/modules/linux/profile_haproxy/manifests/firewall.pp`
- `site/modules/linux/profile_haproxy/templates/haproxy.cfg.erb`
- `site/modules/linux/profile_haproxy/templates/backend.conf.epp`
- `site/modules/linux/profile_haproxy/files/haproxy_errors/503.http`
- `site/modules/linux/profile_haproxy/files/haproxy_errors/408.http`
- `site/modules/linux/profile_haproxy/data/common.yaml`
- `site/modules/linux/profile_haproxy/data/cluster/haproxy_prod_fra.yaml`
- `site/modules/linux/profile_haproxy/lib/facter/haproxy_version.rb`

**Service endpoints to check**:

- **haproxy**: `80/tcp`
- **haproxy**: `443/tcp`
- **haproxy**: `9000/tcp`
- **webservers**: backend port `8080`
- **api**: backend port `3000`
- **internal_monitoring**: backend port `9090`

**Templates rendered**:

- `haproxy.cfg.erb`: `1` reported render
- `backend.conf.epp` for `webservers`: `1` reported render
- `backend.conf.epp` for `api`: `1` reported render
- `backend.conf.epp` for `internal_monitoring`: `1` reported render
- Total reported backend template renders: `3`; verify from evaluated Hiera data
- `503.http`: `1` static copy
- `408.http`: `1` static copy

## Pre-flight checks

```bash
# Common package and service checks
rpm -q haproxy 2>/dev/null || dpkg-query -W -f='${Status}\n' haproxy
systemctl is-enabled haproxy
systemctl is-active haproxy
haproxy -v

# Main configuration validation
haproxy -c -f /etc/haproxy/haproxy.cfg

# Main HAProxy instance
test -d /etc/haproxy
test