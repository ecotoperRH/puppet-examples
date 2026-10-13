---
source-path: modules/profile_haproxy
---

# Migration Plan: profile_haproxy

**TLDR**: This module configures HAProxy on Linux hosts. It installs the HAProxy package and supporting users, groups, directories, configuration files, error responses, optional stick-table configuration, and firewall integration. It renders one main configuration and three backend fragments for the effective production host, exports a local balancer member, imports application members through PuppetDB, validates HAProxy configuration before service management, and ensures the service is running. The Ansible implementation should use defaults plus OS, environment, cluster, and host variables; recursively merge backend dictionaries; replace PuppetDB discovery with inventory or service-discovery data; store the statistics password in Ansible Vault; and explicitly add service enablement and configuration-triggered restarts if those are desired target-state behaviors.

## Service Type and Instances

**Service Type**: Load balancer / reverse proxy

**Configured Instances**:

- **HAProxy service**
  - Package: `haproxy`
  - Configuration directory: `/etc/haproxy`
  - Main configuration: `/etc/haproxy/haproxy.cfg`
  - Runtime state directory: `/var/lib/haproxy`
  - Service name: `haproxy`
  - Service user: `haproxy`
  - Service group: `haproxy`
  - Statistics interface: enabled for `lb01.fra.example.com`; common default is enabled, subject to overrides
  - Statistics port: `9001` on `lb01.fra.example.com`; common default is `9000`
  - Statistics URI: supplied by common Hiera data
  - TLS termination: enabled for production; common default is disabled
  - Backend fragments:
    - `/etc/haproxy/conf.d/webservers.cfg`
    - `/etc/haproxy/conf.d/api.cfg`
    - `/etc/haproxy/conf.d/internal_monitoring.cfg`
  - Error responses:
    - `/etc/haproxy/errors/503.http`
    - `/etc/haproxy/errors/408.http`
  - Stick tables: controlled by environment data
  - Observed Puppet behavior: service is ensured `running`
  - Ansible target behavior: enable the service at boot if required by the migration specification

- **Local HAProxy balancer member**
  - Resource title: local networking FQDN
  - Published endpoint: local networking FQDN
  - Published address: local networking IP
  - Published port: `8080`
  - Listening service classification: `webservers`
  - Health-check option: `check`
  - PuppetDB behavior: exported as `Haproxy::Balancermember`

- **Discovered application member `api-${certname}`**
  - Source: application servers discovered through PuppetDB
  - Listening service: `webservers`
  - Resource type: `Haproxy::Balancermember`
  - Imported by: `Haproxy::Balancermember <| listening_service == 'webservers' |> `
  - Ansible target behavior: use explicit inventory membership, host variables, or an external service registry

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
### Manifests

- site/role/manifests/haproxy.pp
- site/profile/manifests/loadbalancer/haproxy.pp
- site/modules/linux/profile_haproxy/manifests/init.pp
- site/modules/linux/profile_haproxy/manifests/install.pp
- site/modules/linux/profile_haproxy/manifests/config.pp
- site/modules/linux/profile_haproxy/manifests/discover.pp
- site/modules/linux/profile_haproxy/manifests/service.pp
- site/modules/linux/profile_haproxy/manifests/firewall.pp

### Templates referenced by the execution tree

- profile_haproxy/haproxy.cfg.erb
- profile_haproxy/backend.conf.epp

### Custom components

- modules/profile_haproxy/lib/facter/haproxy_version.rb

### Data files used for migration

- modules/profile_haproxy/data/common.yaml
- modules/profile_haproxy/data/os/Debian.yaml
- modules/profile_haproxy/data/environment/production.yaml
- modules/profile_haproxy/data/environment/staging.yaml
- modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml
- modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml
```

## Module Explanation

The module performs operations in this order:

1. **`role::haproxy`** (`site/role/manifests/haproxy.pp`)
   - Executes the Linux-only role path based on `facts['kernel']`.
   - Includes `::profile::base::base`.
   - Includes `::profile::loadbalancer::haproxy`.
   - Reads the `environment` and `kernel` facts.
   - Orders `Class['::profile::base::base']` before `Class['::profile::loadbalancer::haproxy']`.
   - The execution-tree entry reports `exec 'None'` with no command or execution conditions supplied.

2. **`profile::loadbalancer::haproxy`** (`site/profile/manifests/loadbalancer/haproxy.pp`)
   - Includes `profile_haproxy`.
   - Passes execution into the module class.

3. **`profile_haproxy`** (`site/modules/linux/profile_haproxy/manifests/init.pp`)
   - Contains `profile_haproxy::install`.
   - Contains `profile_haproxy::config`.
   - Contains `profile_haproxy::discover`.
   - Contains `profile_haproxy::service`.
   - Contains `profile_haproxy::firewall`.
   - Orders `Class['profile_haproxy::install']` before `Class['profile_haproxy::config']`.
   - Orders `Class['profile_haproxy::config']` before `Class['profile_haproxy::discover']`.
   - Sends a refresh notification from `Class['profile_haproxy::discover']` to `Class['profile_haproxy::service']`.
   - The execution tree does not show configuration files directly notifying or refreshing the service.

4. **`profile_haproxy::install`** (`site/modules/linux/profile_haproxy/manifests/install.pp`)
   - Installs package `haproxy` with `ensure => present`.
   - Creates group `haproxy` with `ensure => present`.
   - Creates user `haproxy` with `ensure => present`.
   - Creates `/etc/haproxy` as a directory.
   - Creates `/etc/haproxy/conf.d` as a directory.
   - Creates `/var/lib/haproxy` as a directory.
   - Iterates over the Debian `extra_packages` array only when it is non-empty; element values are not supplied in the source inventory.
   - Runs `exec 'haproxy_selinux_connect'` when `selinux_enabled` is true; command and guards are not supplied.
   - Ensures package and directory prerequisites exist before configuration rendering.

5. **`profile_haproxy::config`** (`site/modules/linux/profile_haproxy/manifests/config.pp`)
   - Renders `/etc/haproxy/haproxy.cfg` from `profile_haproxy/haproxy.cfg.erb`.
   - Renders the main template once.
   - Uses statistics, connection, TLS, logging, retry, and backend variables.
   - Recursively merges the effective backend collection.
   - Expands the backend iteration into:
     - `webservers` → `/etc/haproxy/conf.d/webservers.cfg`
     - `api` → `/etc/haproxy/conf.d/api.cfg`
     - `internal_monitoring` → `/etc/haproxy/conf.d/internal_monitoring.cfg`
   - Renders `profile_haproxy/backend.conf.epp` three times.
   - The effective `api` backend contains servers `api1-fra` and `api2-fra`.
   - Creates `/etc/haproxy/errors` as a directory.
   - Expands the error-response iteration into:
     - `503` → `/etc/haproxy/errors/503.http`
     - `408` → `/etc/haproxy/errors/408.http`
   - Creates `/etc/haproxy/conf.d/stick-tables.cfg` when `stick_table_enabled` is true.
   - Uses `stick_table_size` and `stick_table_expire` for stick-table configuration.
   - The exact source, ownership, group, and mode for error-response files are not supplied.
   - Puppet deep-merge behavior must be implemented with recursive Ansible dictionary merging.

6. **`profile_haproxy::discover`** (`site/modules/linux/profile_haproxy/manifests/discover.pp`)
   - Exports one local `Haproxy::Balancermember`:
     - Title: local networking FQDN
     - `listening_service`: `webservers`
     - `server_names`: local networking FQDN
     - `ipaddresses`: local networking IP
     - `ports`: `8080`
     - `options`: `check`
   - Collects `Haproxy::Balancermember` resources matching `listening_service == 'webservers'`.
   - Queries PuppetDB for `Profile::App_server` classes.
   - Restricts results to certnames that also have `Profile::Base`.
   - Matches `Profile::Base.parameters.environment` to the current `puppet_environment` fact.
   - Expands `$app_servers.each` into one member titled `api-${certname}` per discovered application server.
   - The actual application-server certname list is generated dynamically by PuppetDB.
   - Ansible should replace this behavior with inventory groups, host/group variables, or an external service registry.

7. **`profile_haproxy::service`** (`site/modules/linux/profile_haproxy/manifests/service.pp`)
   - Ensures service `haproxy` is `running`.
   - Does not provide confirmed Puppet evidence that the service is enabled at boot.
   - Runs `exec 'haproxy_config_check'`; command and guards are not supplied.
   - Creates or manages `/etc/logrotate.d/haproxy`; exact content and permissions are not supplied.
   - Receives the refresh notification from discovery changes.
   - Ansible should run the equivalent of `haproxy -c -f /etc/haproxy/haproxy.cfg` before restart or enablement.
   - Configuration-triggered restarts are an Ansible target behavior to add and verify, not a directly confirmed Puppet relationship.

8. **`profile_haproxy::firewall`** (`site/modules/linux/profile_haproxy/manifests/firewall.pp`)
   - Selects behavior using `firewall_provider`.
   - For `firewalld`:
     - Runs `exec 'firewalld_reload'`; command and guards are not supplied.
     - Explicit firewalld port or service resources are not enumerated.
   - For `ufw`:
     - Installs package `ufw`.
     - Runs `exec 'ufw_allow_http'`.
     - Runs `exec 'ufw_allow_https'`.
     - Runs `exec 'ufw_enable'`.
   - The literal Debian firewall-provider value is not supplied.
   - Ansible should select the provider using `haproxy_firewall_provider`.
   - Unknown providers must fail validation rather than silently continue.

## Variables

**Variable Flow Summary**: 25 common HAProxy variables plus OS-, environment-, cluster-, and host-specific overrides across six data files and five hierarchy levels. Ansible should map Puppet keys to `haproxy_*` variables and recursively merge `haproxy_backends`.

### Variable Definitions

#### `common.yaml` — defaults

Migration note: Base defaults for all nodes.

- `haproxy_package_name`: `haproxy` (type: string)
- `haproxy_config_dir`: `/etc/haproxy` (type: string)
- `haproxy_config_file`: `/etc/haproxy/haproxy.cfg` (type: string)
- `haproxy_service_name`: `haproxy` (type: string)
- `haproxy_user`: `haproxy` (type: string)
- `haproxy_group`: `haproxy` (type: string)
- `haproxy_stats_enabled`: `true` (type: boolean)
- `haproxy_stats_port`: `9000` (type: integer)
- `haproxy_stats_uri`: literal value not supplied (type: string)
- `haproxy_stats_user`: literal value not supplied (type: string)
- `haproxy_stats_password`: encrypted Hiera eyaml value not exposed (type: string)
- `haproxy_global_maxconn`: `4096` (type: integer)
- `haproxy_client_timeout`: `30s` (type: string)
- `haproxy_server_timeout`: `30s` (type: string)
- `haproxy_connect_timeout`: literal value not supplied (type: string)
- `haproxy_retries`: literal value not supplied (type: integer)
- `haproxy_ssl_enabled`: `false` (type: boolean)
- `haproxy_ssl_cert_path`: path value not supplied (type: string)
- `haproxy_ssl_key_path`: path value not supplied (type: string)
- `haproxy_ssl_ciphers`: common AES128 cipher suite; exact suite not supplied (type: string)
- `haproxy_ssl_min_version`: `TLSv1.2` (type: string)
- `haproxy_log_server`: literal value not supplied (type: string)
- `haproxy_log_facility`: literal value not supplied (type: string)
- `haproxy_log_level`: `info` (type: string)
- `haproxy_backends`: includes `webservers` and `api` (type: hash)

#### `os/Debian.yaml` — OS-specific values

Migration note: Debian-specific variables, loaded conditionally for Debian hosts. Literal values not supplied are source-inventory claims requiring separate verification.

- `haproxy_package_name`: `haproxy` (type: string)
- `haproxy_config_dir`: `/etc/haproxy` (type: string)
- `haproxy_firewall_provider`: literal value not supplied (type: string)
- `haproxy_extra_packages`: elements not supplied (type: array)

#### `environment/production.yaml` — production values

Migration note: Production-specific overrides.

- `haproxy_global_maxconn`: `16384` (type: integer)
- `haproxy_ssl_enabled`: `true` (type: boolean)
- `haproxy_log_level`: `warning` (type: string)
- `haproxy_client_timeout`: `60s` (type: string)
- `haproxy_server_timeout`: `60s` (type: string)
- `haproxy_stats_enabled`: literal value not supplied (type: boolean)
- `haproxy_stick_table_enabled`: literal value not supplied (type: boolean)
- `haproxy_stick_table_size`: literal value not supplied (type: string)
- `haproxy_stick_table_expire`: literal value not supplied (type: string)

#### `environment/staging.yaml` — staging values

Migration note: Staging-specific overrides at the same environment hierarchy level as production.

- `haproxy_global_maxconn`: `2048` (type: integer)
- `haproxy_ssl_enabled`: `false` (type: boolean)
- `haproxy_log_level`: `debug` (type: string)
- `haproxy_stats_enabled`: `true` (type: boolean)
- `haproxy_stick_table_enabled`: literal value not supplied (type: boolean)

#### `cluster/haproxy_prod_fra.yaml` — cluster values

Migration note: Cluster-specific overrides for the production Frankfurt HAProxy cluster.

- `haproxy_global_maxconn`: `32768` (type: integer)
- `haproxy_ssl_ciphers`: cluster AES256 cipher suite; exact suite not supplied (type: string)
- `haproxy_ssl_min_version`: `TLSv1.3` (type: string)
- `haproxy_backends`: contribution containing `internal_monitoring` (type: hash)

#### `nodes/lb01.fra.example.com.yaml` — host values

Migration note: Host-specific overrides for `lb01.fra.example.com`.

- `haproxy_stats_enabled`: `true` (type: boolean)
- `haproxy_stats_port`: `9001` (type: integer)
- `haproxy_backends`: contribution whose `api.servers` contains `api1-fra` and `api2-fra` (type: hash)

### Effective Production Host Values

For `lb01.fra.example.com` in production and cluster `haproxy_prod_fra`:

- `haproxy_package_name`: `haproxy`
- `haproxy_config_dir`: `/etc/haproxy`
- `haproxy_config_file`: `/etc/haproxy/haproxy.cfg`
- `haproxy_service_name`: `haproxy`
- `haproxy_user`: `haproxy`
- `haproxy_group`: `haproxy`
- `haproxy_global_maxconn`: `32768`
- `haproxy_client_timeout`: `60s`
- `haproxy_server_timeout`: `60s`
- `haproxy_ssl_enabled`: `true`
- `haproxy_ssl_min_version`: `TLSv1.3`
- `haproxy_ssl_ciphers`: cluster AES256 cipher suite
- `haproxy_log_level`: `warning`
- `haproxy_stats_enabled`: `true`
- `haproxy_stats_port`: `9001`
- `haproxy_backends`: recursively merged `webservers`, `api`, and `internal_monitoring` definitions
- `api.servers`: `api1-fra`, `api2-fra`
- `haproxy_stats_password`: encrypted secret retrieved from Ansible Vault
- `haproxy_firewall_provider`: Debian-specific value not supplied
- `haproxy_extra_packages`: Debian-specific array not supplied

### Variable Migration Summary

- **Common defaults**: 25 variables from `common.yaml`
- **OS-specific variables**: 4 variables from `os/Debian.yaml`
- **Environment-specific variables**: 9 production variables and 5 staging variables
- **Cluster-specific variables**: 4 variables
- **Host-specific variables**: 3 variables
- **Encrypted variables**: 1 concrete HAProxy secret, `haproxy_stats_password`
- **Sensitive file references**:
  - `haproxy_ssl_cert_path`
  - `haproxy_ssl_key_path`

The six data files represent five hierarchy levels: common, OS, environment, cluster, and node.

### Cross-Level Overrides

- `haproxy_global_maxconn`: common `4096` → production `16384` → cluster `32768`
- `haproxy_ssl_ciphers`: common AES128 suite → cluster AES256 suite
- `haproxy_ssl_min_version`: common `TLSv1.2` → cluster `TLSv1.3`
- `haproxy_ssl_enabled`: common `false` → production `true`
- `haproxy_client_timeout`: common `30s` → production `60s`
- `haproxy_server_timeout`: common `30s` → production `60s`
- `haproxy_log_level`: common `info` → production `warning`; staging uses `debug`
- `haproxy_stats_enabled`: common `true` → production value not supplied → host `true`
- `haproxy_stats_port`: common `9000` → host `9001`
- `haproxy_backends`: recursively merged across common, cluster, and host levels
  - Common contributes `webservers` and `api`
  - Cluster contributes `internal_monitoring`
  - Host contributes `api.servers` containing `api1-fra` and `api2-fra`

### Merge Strategy Notes

- `haproxy_backends` uses recursive/deep merging so nested backend and server values are preserved.
- Variables using `hash` merge combine values from multiple levels with shallow merging.
- Variables using `deep` merge recursively combine nested hash values.
- Variables using `first` use the first value found and do not merge.
- Scalar overrides use the effective value from the highest-priority applicable hierarchy level.

### Sensitive Data Migration

- `haproxy_stats_password`
  - Stored as encrypted Hiera eyaml.
  - Store as `haproxy_stats_password` in Ansible Vault or an external secret provider.
  - Do not place it in `defaults/main.yml`.
  - Use `no_log: true` for secret retrieval and secret-bearing tasks.
  - Restrict the rendered HAProxy configuration if the password is stored in clear text.

- `haproxy_ssl_cert_path`
  - References TLS certificate material.
  - Certificate contents were not supplied.
  - Deploy certificate files separately with restrictive permissions if Ansible owns them.

- `haproxy_ssl_key_path`
  - References TLS private-key material.
  - Store private-key contents in Vault or a certificate-management system.
  - The path alone does not prove that the key is securely managed.

- Redis and APT credentials found in broader dependency scans are not direct resources in this execution tree and are excluded from this role.

## Custom Types and Providers

### Custom Facter Fact: `haproxy_version`

- File: `modules/profile_haproxy/lib/facter/haproxy_version.rb`
- Platform: Linux only
- Reported command: `haproxy -v 2>/dev/null`
- Reported extraction: semantic version matching `version\s+(\d+\.\d+\.\d+)`
- Return value:
  - Captured version when HAProxy is installed and output matches
  - `nil` when HAProxy is unavailable or output does not match
- Ansible equivalent:
  - Add a custom fact under `facts.d`, or
  - Gather the installed version with Ansible package facts
- No resource parameters are associated with this fact.
- The command and regular expression require verification against the source file because the supplied structured summary did not include its contents.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` version `9.7.0`
- `puppetlabs-concat` version `9.0.2`
- `puppetlabs-firewall` version `8.1.3`
- `puppetlabs-vcsrepo` version `6.1.0`
- `puppet-redis` version `11.0.0`
- `puppetlabs-apt` version `9.4.0`

These dependencies are not automatically required in the Ansible role. The execution tree does not show direct Redis, repository, or VCS resources.

**System package dependencies**:

- `haproxy`
- `ufw` when `haproxy_firewall_provider` is `ufw`
- Values contained in `haproxy_extra_packages`

**Service dependencies**:

- Installation completes before configuration.
- Configuration completes before discovery.
- Discovery changes notify the HAProxy service.
- Configuration validation runs before service restart or enablement.
- Configuration directories exist before configuration files are rendered.
- Configuration-triggered service restarts are an Ansible target behavior and must be explicitly implemented and tested.

## Puppet Facts Used

- `facts['kernel']`
  - Determines whether the Linux-only role path executes.
- `facts['networking']['fqdn']`
  - Supplies the local exported balancer-member server name and resource title.
- `facts['networking']['ip']`
  - Supplies the local exported balancer-member address.
- `facts['puppet_environment']`
  - Filters PuppetDB application-server discovery.
- `fact('environment')`
  - Is read by the load-balancer profile chain.
- `haproxy_version`
  - Custom Linux fact returning the installed HAProxy semantic version.

## Template Conversion Notes

### `profile_haproxy/haproxy.cfg.erb`

- Render destination: `/etc/haproxy/haproxy.cfg`
- Render count: 1
- Reported variables: 21
- Reported logic blocks: 5
- Inputs:
  - Statistics settings
  - Connection limits and timeouts
  - Retry count
  - TLS settings
  - Logging settings
  - Backend definitions
- Conditional rendering covers statistics, TLS, and backend behavior.
- Exact Ruby variable names and expressions were not included in the supplied source inventory and require direct template verification.

### `profile_haproxy/backend.conf.epp`

- Render destinations:
  - `/etc/haproxy/conf.d/webservers.cfg`
  - `/etc/haproxy/conf.d/api.cfg`
  - `/etc/haproxy/conf.d/internal_monitoring.cfg`
- Render count: 3
- Reported variables: 11
- Reported logic blocks: 5
- Iterates over backend-specific configuration and server definitions.
- The `api` backend renders `api1-fra` and `api2-fra`.
- Exact EPP variable names and expressions were not included in the supplied source inventory and require direct template verification.

### Non-template Generated Files

- `/etc/haproxy/errors/503.http`
- `/etc/haproxy/errors/408.http`
- `/etc/haproxy/conf.d/stick-tables.cfg` when enabled
- `/etc/logrotate.d/haproxy`

Source content and exact file modes for these resources require implementation-time verification.

## PuppetDB Dependencies

**Context**: PuppetDB is used for cross-node balancer-member sharing and application-server discovery.

### Exported Resources

- Resource type: `Haproxy::Balancermember`
- Resource title: local networking FQDN
- Export syntax: `@@haproxy::balancermember['<local networking FQDN>']`
- Exported attributes:
  - `listening_service`: `webservers`
  - `server_names`: local networking FQDN
  - `ipaddresses`: local networking IP
  - `ports`: `8080`
  - `options`: `check`
- Migration note: replace cross-node exported resources with explicit HAProxy peer inventory, backend host variables, or service-discovery data.

### Resource Collectors

- Collector: `Haproxy::Balancermember <| listening_service == 'webservers' |> `
- Returned data: all exported balancer members classified as `webservers`
- Migration note: inventory or service-discovery membership must provide the same application and peer endpoint data.

### PuppetDB Queries

- Query target: `Class` resources titled `Profile::App_server`
- Required relationship: matching `Profile::Base` resource
- Filter: `Profile::Base.parameters.environment` equals the current `puppet_environment`
- Returned data: application-server certnames
- Resource expansion: one `api-${certname}` balancer member per returned certname
- Migration note: represent environment filtering through inventory groups, host variables, or an external service registry.

### Host Identity Data

- Local networking FQDN identifies the exported local balancer member.
- Local networking IP identifies the exported member address.
- Application-server certnames identify discovered backend members.
- `puppet_environment` identifies the deployment environment used for discovery filtering.

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
- `profile_haproxy/haproxy.cfg.erb`
- `profile_haproxy/backend.conf.epp`
- `modules/profile_haproxy/data/common.yaml`
- `modules/profile_haproxy/data/os/Debian.yaml`
- `modules/profile_haproxy/data/environment/production.yaml`
- `modules/profile_haproxy/data/environment/staging.yaml`
- `modules/profile_haproxy/data/cluster/haproxy_prod_fra.yaml`
- `modules/profile_haproxy/data/nodes/lb01.fra.example.com.yaml`
- `modules/profile_haproxy/lib/facter/haproxy_version.rb`

**Service endpoints to check**:

- **HAProxy statistics on `lb01.fra.example.com`**: port `9001`
- **HAProxy statistics default**: port `9000` on hosts without the node override
- **Local HAProxy balancer member**: port `8080`
- **HTTP firewall access**: selected firewall provider
- **HTTPS firewall access**: selected firewall provider
- **Discovered `webservers` application members**: ports supplied by inventory or service discovery

**Templates rendered**:

- `profile_haproxy/haproxy.cfg.erb`: 1 render
- `profile_haproxy/backend.conf.epp` for `webservers`: 1 render
- `profile_haproxy/backend.conf.epp` for `api`: 1 render
- `profile_haproxy/backend.conf.epp` for `internal_monitoring`: 1 render

## Pre-flight checks

```bash
# Confirm Linux host
test "$(uname -s)" = "Linux"

# HAProxy service instance
dpkg-query -W -f='${Status}\n' haproxy
getent passwd haproxy
getent group haproxy
test -d /etc/haproxy
test -d /etc/haproxy/conf.d
test -d /var/lib/haproxy
test -f /etc/haproxy/haproxy.cfg
systemctl status haproxy --no-pager

# Local HAProxy balancer member
getent hosts "$(hostname -f)"
ss -ltn | grep ':8080'

# HAProxy statistics instance on lb01.fra.example.com
ss -ltn | grep ':9001'

# Default statistics endpoint on hosts without the lb01 override
ss -ltn | grep ':9000'

# Backend instance: webservers
test -f /etc/haproxy/conf.d/webservers.cfg
grep -q 'webservers' /etc/haproxy/haproxy.cfg

# Backend instance: api
test -f /etc/haproxy/conf.d/api.cfg
grep -q 'api1-fra' /etc/haproxy/conf.d/api.cfg
grep -q 'api2-fra' /etc/haproxy/conf.d/api.cfg

# Backend instance: internal_monitoring
test -f /etc/haproxy/conf.d/internal_monitoring.cfg
grep -q 'internal_monitoring' /etc/haproxy/haproxy.cfg

# Error-response instances
test -d /etc/haproxy/errors
test -f /etc/haproxy/errors/503.http
test -f /etc/haproxy/errors/408.http

# Optional stick-table instance
if [ "${HAPROXY_STICK_TABLE_ENABLED:-false}" = "true" ]; then
  test -f /etc/haproxy/conf.d/stick-tables.cfg
fi

# Validate complete HAProxy configuration
haproxy -c -f /etc/haproxy/haproxy.cfg

# Verify effective production values
grep -q '32768' /etc/haproxy/haproxy.cfg
grep -q '60s' /etc/haproxy/haproxy.cfg
grep -q 'TLSv1.3' /etc/haproxy/haproxy.cfg
grep -q 'warning' /etc/haproxy/haproxy.cfg
grep -q ':9001' /etc/haproxy/haproxy.cfg

# Firewall instance
test -f /etc/ufw/user.rules || command -v firewall-cmd >/dev/null
# Verify HTTP and HTTPS rules using the selected provider.

# Logrotate instance
test -f /etc/logrotate.d/haproxy

# Observed Puppet service state
systemctl is-active haproxy

# Ansible target-state service enablement, if intentionally implemented
systemctl is-enabled haproxy

# Confirm secret handling
# Verify haproxy_stats_password is sourced from Vault and absent from task output.
```