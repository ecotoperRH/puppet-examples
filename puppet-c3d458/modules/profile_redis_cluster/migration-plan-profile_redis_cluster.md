---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module installs and configures one implicit Redis `default` instance through the vendored `puppet-redis` dependency. Redis listens on `0.0.0.0:6379`, uses `/var/run/redis/redis.sock`, enables AOF persistence with `everysec` fsync, sets `maxmemory` to `2048mb`, and leaves `maxmemory-policy` at the Redis dependency default because the profile parameter is not propagated. Client authentication defaults insecurely to `CHANGEME` and must be migrated to Ansible Vault. Migration must preserve package installation, configuration directories, the generated configuration and copy workflow, service management, and removal of the obsolete systemd limit drop-in. The module also performs an unused PuppetDB query and defines an unused `redis_role` fact.

## Service Type and Instances

**Service Type**: Redis key-value database/cache

**Configured Instances**:

- **default**: Implicit Redis instance created because `default_install=true`; no explicit instances are configured.
  - Location/Path: `/etc/redis/redis.conf`
  - Original Puppet-managed configuration path: `/etc/redis/redis.conf.puppet`
  - Data directory: `/var/lib/redis`
  - Log directory: `/var/log/redis`
  - Service name: `redis-server`
  - Port/Socket: TCP `0.0.0.0:6379`; Unix socket `/var/run/redis/redis.sock`
  - Bind address: `0.0.0.0`
  - Authentication: `requirepass` defaults to `CHANGEME`; production migration must use Ansible Vault
  - Maximum memory: `2048mb`
  - Eviction policy: Redis dependency default; `allkeys-lru` is declared by the profile but is not passed to `redis`
  - Persistence: AOF enabled with `everysec` fsync
  - Cluster mode: disabled
  - TLS: disabled
  - Explicit instance loop: zero iterations because `instances={}`
  - Instance creation: one implicit `redis::instance 'default'`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
site/role/manifests/redis_cluster.pp
site/profile/manifests/cache/redis.pp
modules/profile_redis_cluster/manifests/init.pp
modules/profile_redis_cluster/manifests/install.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp
modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp
modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/redis.conf.epp
modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/service_templates/redis.service.epp
modules/profile_redis_cluster/lib/facter/redis_role.rb
test/data/common.yaml
data/common.yaml
data/environment/production.yaml
data/environment/staging.yaml
```

The structured analysis reports 86 analyzed files, but the supplied migration input identifies only the files above. The remaining analyzed files are not enumerated in the supplied data. Before migration, inventory and classify all additional files, including any `params.pp`, tests, metadata, custom types/providers, and supporting code, and record whether each requires migration, is unrelated metadata, or is test-only.

## Module Explanation

The module performs operations in this order:

1. **`role::redis_cluster`** (`site/role/manifests/redis_cluster.pp`):
   - Evaluates the Linux-only condition `$facts['kernel'].downcase == 'linux'`.
   - Contains `exec[Exec]`, but its command and attributes are absent from the supplied execution data; obtain the role manifest details before migrating this resource.
   - Includes `::profile::base::base`, which must be migrated separately or provided by an existing Ansible prerequisite role.
   - Includes `::profile::cache::redis`.
   - Enforces `Class['::profile::base::base'] -> Class['::profile::cache::redis']`.
   - Uses `$facts['kernel']` for the kernel name and references `fact('environment')` for the Puppet environment.

2. **`profile::cache::redis`** (`site/profile/manifests/cache/redis.pp`):
   - Includes `profile_redis_cluster`.
   - Defines no additional resources in the supplied execution tree.
   - Delegates PuppetDB-dependent discovery to `profile_redis_cluster`.

3. **`profile_redis_cluster`** (`modules/profile_redis_cluster/manifests/init.pp`):
   - Uses `redis_port=6379` as an integer.
   - Uses `redis_password='CHANGEME'` as a plaintext string unless overridden.
   - Uses `maxmemory_mb=2048` as an integer.
   - Declares `maxmemory_policy='allkeys-lru'`, but does not pass it to the Redis dependency.
   - Contains `profile_redis_cluster::install`.
   - Executes the unused PuppetDB query `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`.
   - Stores the query result in `$redis_nodes`; no subsequent resource uses it.

4. **`profile_redis_cluster::install`** (`modules/profile_redis_cluster/manifests/install.pp`):
   - Declares the vendored `redis` class with:
     - `bind=0.0.0.0`
     - `port=6379`
     - `requirepass=CHANGEME`
     - `maxmemory=2048mb`
     - `appendonly=true`
     - `appendfsync=everysec`
     - `manage_package=true`
   - Enforces `redis::preinstall -> redis::install -> redis::config`.
   - Because `notify_service=true`, configuration changes notify `redis::service`.

5. **`redis`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`):
   - Inherits `redis::params`.
   - Applies the effective profile overrides listed above.
   - Uses dependency defaults of `default_install=true`, `manage_repo=false`, `dnf_module_stream=undef`, `service_manage=true`, `ulimit=65536`, `ulimit_managed=true`, `managed_by_cluster_manager=false`, and `manage_service_file=false`.
   - Uses Debian-style defaults for the active path: package `redis-server`, service `redis-server`, configuration directory `/etc/redis`, configuration file `/etc/redis/redis.conf`, original configuration file `/etc/redis/redis.conf.puppet`, log directory `/var/log/redis`, and work directory `/var/lib/redis`.
   - Uses configuration owner/group `root:root`, configuration mode `0640`, service user/group `redis:redis`, and work-directory mode `0750`.
   - Contains `redis::preinstall`, `redis::install`, `redis::config`, and `redis::service`.
   - Expands `$instances.each |$key, $values|` zero times because `instances={}`.
   - Creates exactly one implicit `redis::instance 'default'` through the `default_install=true` branch.
   - Enforces `Class['redis::preinstall'] -> Class['redis::install'] -> Class['redis::config']`.
   - Sends configuration refresh notifications to `Class['redis::service']`.

6. **`redis::preinstall`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`):
   - Evaluates `$facts['os']['name']` and `$facts['os']['family']`.
   - Does not manage repositories because `manage_repo=false`.
   - Skips the Ubuntu PPA and Debian Redis APT repository branches.
   - Creates no APT repositories or signing keys.

7. **`redis::install`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`):
   - Installs package `redis-server` with `ensure=installed` on the Debian-style active path.
   - Uses the package provider selected by the target operating system.
   - Skips `redis::dnfmodule` because `dnf_module_stream=undef`.
   - If a stream is later configured on Red Hat, the `dnfmodule` provider manages package `redis` with the selected stream and `enable_only=true`.

8. **`redis::dnfmodule`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`):
   - Is conditional and inactive for the current profile.
   - Would execute only when `dnf_module_stream` is defined and the operating-system family is `RedHat`.
   - Would configure the `redis` DNF module using provider `dnfmodule`.

9. **`redis::config`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`):
   - Creates `/etc/redis` as a directory using the dependency default directory mode and owner/group `root:root`.
   - Creates `/var/log/redis` as a directory owned by `redis:redis` using the dependency default log-directory mode.
   - Creates `/var/lib/redis` as a directory owned by `redis:redis` with mode `0750`.
   - Creates `redis::instance 'default'` because `default_install=true`.
   - Includes `redis::ulimit` because `ulimit_managed=true`.
   - On Debian, creates `/etc/default/redis-server` as a `root:root` file with mode `0640`.
   - On non-Debian systems, skips `/etc/default/redis-server`.

10. **`redis::instance 'default'`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`):
    - Resolves the PID file to the dependency default, commonly `/var/run/redis/redis-server.pid`.
    - Uses log file `redis.log`, Unix socket `/var/run/redis/redis.sock`, work directory `/var/lib/redis`, service `redis-server`, and empty ACLs.
    - Uses the dependency daemonization default, generally `false` for systemd-managed Redis.
    - Renders `/etc/redis/redis.conf.puppet` from `redis/redis.conf.epp`.
    - Uses owner/group `root:root` and mode `0640`.
    - Creates `exec[copy /etc/redis/redis.conf.puppet to /etc/redis/redis.conf]` with command `cp -p /etc/redis/redis.conf.puppet /etc/redis/redis.conf`, path `/usr/bin:/bin`, and `refreshonly=true`.
    - The copy exec subscribes to `file[/etc/redis/redis.conf.puppet]` and runs when that generated source file changes.
    - Skips non-default filename logic, per-instance log/work directories, custom systemd unit creation, generated service ordering, and deferred-value handling.
    - The enclosing Redis class notifies `redis::service` after configuration changes.

11. **`redis::ulimit`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`):
    - Skips `/etc/security/limits.d/redis.conf` because `managed_by_cluster_manager=false`.
    - Removes the obsolete `/etc/systemd/system/redis-server.service.d/limit.conf` with `ensure=absent`.
    - Migration must preserve this cleanup and must not create new Redis systemd limits based on the supplied execution path.

12. **`redis::service`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`):
    - Manages `service[redis-server]` with `ensure=running` and `enable=true`.
    - Receives refresh notifications from Redis configuration changes.

### Active Resource Reconciliation

- `role::redis_cluster`: one Linux-conditional `exec[Exec]`; command and attributes require source confirmation.
- `profile::cache::redis`: no direct resources.
- `profile_redis_cluster`: one contained install class and one unused PuppetDB query.
- `redis`: four contained classes and one implicit `redis::instance 'default'`.
- Explicit `$instances.each` resources: zero.
- `redis::preinstall`: zero repository/key resources.
- `redis::install`: one `redis-server` package.
- `redis::dnfmodule`: zero active resources; conditional Red Hat stream path only.
- `redis::config`: three directories, one default instance, one ulimit cleanup class, and one Debian-only `/etc/default/redis-server` file.
- `redis::instance 'default'`: one generated source configuration file and one refresh-only copy exec.
- `redis::ulimit`: one active cleanup file resource; the security-limits file is skipped.
- `redis::service`: one enabled and running `redis-server` service.
- `redis/service_templates/redis.service.epp`: zero renders.

## Variables

**Variable Flow Summary**: Four manifest parameters, two test-only Redis values with omitted concrete fixture values in the supplied analysis, zero active production Redis Hiera overrides, and platform-dependent dependency defaults across the available data files. The supplied input does not include the Hiera `hierarchy:` declaration, so exact lookup precedence for `test/data/common.yaml` cannot be confirmed.

### Variable Definitions

#### Profile manifest defaults

- `profile_redis_cluster::redis_port`: `6379` (type: integer)
- `profile_redis_cluster::redis_password`: `CHANGEME` (type: string; insecure plaintext placeholder)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: integer)
- `profile_redis_cluster::maxmemory_policy`: `allkeys-lru` (type: string; declared but not passed to the Redis class)

#### `test/data/common.yaml` — test data level

- `profile_redis_cluster::redis_password`: exact fixture value not present in the supplied analysis (type: string; plaintext test value)
- `profile_redis_cluster::maxmemory_mb`: exact fixture value not present in the supplied analysis (type: integer)
- These values apply only when the test Hiera data source is explicitly enabled.
- Their precedence relative to manifest defaults cannot be asserted without the configured Hiera hierarchy.
- The password must be moved to Ansible Vault and must not be committed as plaintext.

#### `data/common.yaml` — common production defaults

- `ntp::servers`: value not material to this module (type: array)
- `ssh::client_alive_interval`: value not material to this module (type: integer)
- `ssh::permit_root_login`: value not material to this module (type: boolean)
- `syslog::server`: value not material to this module (type: string)
- `syslog::facility`: value not material to this module (type: string)
- No active Redis variables are defined in the supplied file.

#### `data/environment/production.yaml` — production environment

- `ntp::servers`: value not material to this module (type: array)
- `syslog::server`: value not material to this module (type: string)
- `syslog::facility`: value not material to this module (type: string)
- No active Redis variables are defined in the supplied file.

#### `data/environment/staging.yaml` — staging environment

- `syslog::server`: value not material to this module (type: string)
- No active Redis variables are defined in the supplied file.

#### Suggested Ansible mapping

```yaml
redis_cluster_port: 6379
redis_cluster_password: "{{ vault_redis_cluster_password }}"
redis_cluster_maxmemory_mb: 2048
redis_cluster_maxmemory_policy: allkeys-lru
redis_bind: "0.0.0.0"
redis_package_name: redis-server
redis_service_name: redis-server
redis_config_dir: /etc/redis
redis_config_file: /etc/redis/redis.conf
redis_config_source_file: /etc/redis/redis.conf.puppet
redis_log_dir: /var/log/redis
redis_data_dir: /var/lib/redis
redis_socket: /var/run/redis/redis.sock
redis_ulimit: 65536
```

### Variable Migration Summary

- **Common defaults relevant to Redis**: 0 active production variables from `data/common.yaml`
- **OS-specific variables**: dependency defaults for package, service, paths, directory modes, and repository behavior
- **Environment-specific Redis variables**: 0 supplied
- **Host-specific Redis variables**: 0 supplied
- **Test-only Redis variables**: 2
- **Encrypted variables required**: 1 primary configured password, plus optional replication, Sentinel, client-authentication, and TLS secrets if those features are enabled

### Cross-Level Overrides

- `profile_redis_cluster::redis_password`: defined by the manifest default and `test/data/common.yaml`; exact test precedence is unconfirmed because no Hiera hierarchy declaration was supplied.
- `profile_redis_cluster::maxmemory_mb`: defined by the manifest default and `test/data/common.yaml`; exact test precedence is unconfirmed for the same reason.
- No production or staging environment file overrides either variable.
- No `lookup_options` or merge strategy is supplied.
- `maxmemory_policy` is declared by the profile but is not propagated to Redis; Ansible should explicitly configure `allkeys-lru` only if that behavior is intended.

### Merge Strategy Notes

- No explicit `hash` or `deep` merge configuration was supplied.
- Variables use Puppet's default first-value lookup behavior unless the unavailable Hiera configuration specifies otherwise.
- Hash values such as Redis configuration maps must not be assumed to merge without confirmation of `lookup_options`.

### Secret Handling

- `profile_redis_cluster::redis_password` is used as Redis `requirepass` and defaults to `CHANGEME`.
- Store the migrated value as `vault_redis_cluster_password`.
- Use `no_log: true` for tasks that may expose the password.
- Render configuration with restrictive permissions, preferably `0600` when credentials are present.
- Store optional `masterauth`, Sentinel `auth_pass`/`requirepass`, and TLS key material in Ansible Vault.
- No EYAML `ENC[PKCS7,...]` values or external secret provider were detected.
- The plaintext `CHANGEME` default must not be retained in production Ansible variables.

## Custom Types and Providers

### Custom fact: `redis_role`

- File: `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- Scope: Linux only.
- Reads `/etc/redis/conf.d/replica.conf`.
- Returns `replica` when the file exists and contains `replicaof`.
- Returns `primary` otherwise.
- Ansible equivalent: use `stat` and `slurp` under a Linux condition, then set `redis_role` to `replica` or `primary`.
- The supplied execution tree does not show this fact being consumed.

### Providers

- Normal Redis package management uses the platform package provider.
- The inactive Red Hat module-stream path uses provider `dnfmodule`.
- No custom Puppet resource type or custom provider was identified in the supplied file inventory.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.6.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

**System package dependencies**:

- `redis-server` with `ensure=installed` on the active Debian-style path.
- No repository package or signing key is created because `manage_repo=false`.
- No DNF module resource is created because `dnf_module_stream=undef`.

**Service dependencies**:

- `Class['::profile::base::base'] -> Class['::profile::cache::redis']`
- `redis::preinstall -> redis::install -> redis::config`
- `redis::config ~> redis::service`
- `exec[copy /etc/redis/redis.conf.puppet to /etc/redis/redis.conf]` is `refreshonly` and subscribes to `file[/etc/redis/redis.conf.puppet]`.
- The service must be restarted or refreshed after the generated configuration changes.
- Migration must remove, but not recreate, `/etc/systemd/system/redis-server.service.d/limit.conf`.

## Puppet Facts Used

- `$facts['kernel']`: operating-system kernel name; controls the Linux-only role execution.
- `$facts['os']['name']`: operating-system distribution name; used by repository logic.
- `$facts['os']['family']`: operating-system family; controls Debian default-file handling and Red Hat DNF module validation.
- `fact('environment')`: Puppet environment name referenced by the role context.
- `redis_role`: custom fact identifying `replica` versus `primary` from `/etc/redis/conf.d/replica.conf`; not consumed by a Redis resource in the supplied execution tree.

## Template Conversion Notes

### `redis/redis.conf.epp`

- Source: `modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/redis.conf.epp`
- Render count: 1 for `redis::instance 'default'`.
- Destination: `/etc/redis/redis.conf.puppet`, followed by a copy to `/etc/redis/redis.conf`.
- Owner/group: `root:root`.
- Mode: `0640`.
- The supplied template analysis lists its effective parameters and output workflow but does not provide a separate count or description of non-trivial EPP conditionals or iterations. Confirm the template logic before implementation; do not assume that parameter enumeration is a complete logic analysis.
- Effective values include:
  - `port=6379`
  - `bind_arr=['0.0.0.0']`
  - `unixsocket=/var/run/redis/redis.sock`
  - `protected_mode=true`
  - `databases=16`
  - `save_db_to_disk=true`
  - `save_db_to_disk_interval={'900' => '1', '300' => '10', '60' => '10000'}`
  - `requirepass=CHANGEME`
  - `maxmemory=2048mb`
  - `maxmemory_policy=undef`
  - `appendonly=true`
  - `appendfilename=appendonly.aof`
  - `appendfsync=everysec`
  - `cluster_enabled=false`
  - `tls_port=undef`
  - `tls_auth_clients=no`
  - `tls_replication=false`
  - `tls_cluster=false`
  - `acls=[]`
  - `custom_options={}`
- Ansible should render the effective Redis configuration directly unless compatibility with the `.puppet` source-and-copy workflow is required.

### `redis/service_templates/redis.service.epp`

- Source: `modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/service_templates/redis.service.epp`
- Render count: 0 for the active profile.
- The template renders only when `manage_service_file=true`, which is false for the default instance.
- It contains five logic blocks and would use `bin_path`, `instance_title`, `port`, `redis_file_name`, `service_name`, `service_user`, service start/stop timeouts, `ulimit`, and `ulimit_managed`.
- Ansible should use the distribution-provided `redis-server.service` unless custom multi-instance behavior is introduced.

## PuppetDB Dependencies

**Context**: The module performs one infrastructure query but does not use its result.

- **PuppetDB Query**:
  - Exact query: `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`
  - Returned data: certificate names of nodes reporting the `Profile_redis_cluster` class.
  - Storage: `$redis_nodes`.
  - Usage: none; no subsequent resource consumes the result.
  - Migration: omit the query unless future behavior requires Redis-node discovery. If required, use Ansible inventory group membership or a service-discovery source.

- **Exported Resources**: none; no `@@` resources are present.
- **Resource Collectors**: none; no `<<| |>>` collectors are present.
- **Host Identity Data**: no per-host PuppetDB identity data is consumed beyond the unused certificate-name query.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/redis_cluster.pp`
- `site/profile/manifests/cache/redis.pp`
- `modules/profile_redis_cluster/manifests/init.pp`
- `modules/profile_redis_cluster/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/redis.conf.epp`
- `modules/profile_redis_cluster/migration-dependencies/redis/templates/redis/service_templates/redis.service.epp`
- `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- `test/data/common.yaml`
- `data/common.yaml`
- `data/environment/production.yaml`
- `data/environment/staging.yaml`
- All additional files included in the reported 86-file analysis, after their disposition is documented.

**Service endpoints to check**:

- **default**: TCP `0.0.0.0:6379`
- **default**: Unix socket `/var/run/redis/redis.sock`

**Templates rendered**:

- **default**: `redis/redis.conf.epp` — 1 render
- **default**: `redis/service_templates/redis.service.epp` — 0 renders

## Pre-flight checks

```bash
# Confirm operating system and package selection
. /etc/os-release
printf 'OS=%s\n' "$ID"
command -v apt-get || true
command -v dnf || true

# Verify the default instance directories
stat -c '%U:%G %a %n' /etc/redis
stat -c '%U:%G %a %n' /var/lib/redis
stat -c '%U:%G %a %n' /var/log/redis

# Verify the default instance configuration files
test -f /etc/redis/redis.conf
test -S /var/run/redis/redis.sock || true
stat -c '%U:%G %a %n' /etc/redis/redis.conf

# Confirm the production password is supplied securely and is not CHANGEME
test -n "${REDIS_PASSWORD:-}"
test "${REDIS_PASSWORD}" != "CHANGEME"

# Validate Redis configuration
redis-server --test-memory 2
redis-server /etc/redis/redis.conf --check-config

# Verify the default instance service
systemctl is-enabled redis-server
systemctl is-active redis-server

# Verify the default instance TCP endpoint
ss -ltnp | grep ':6379'

# Verify the default instance Unix socket
test -S /var/run/redis/redis.sock

# Verify authentication for the default instance
redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_PASSWORD" ping

# Verify AOF persistence for the default instance
test -f /var/lib/redis/appendonly.aof || test -d /var/lib/redis/appendonlydir

# Verify obsolete systemd-limit cleanup
test ! -e /etc/systemd/system/redis-server.service.d/limit.conf

# Verify the custom fact if it is migrated
if test -f /etc/redis/conf.d/replica.conf && grep -q replicaof /etc/redis/conf.d/replica.conf; then
  echo "redis_role=replica"
else
  echo "redis_role=primary"
fi
```