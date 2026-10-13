---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module installs and manages one Redis instance named `default` through the vendored `puppet-redis` dependency. The instance listens on `0.0.0.0:6379`, uses `/var/run/redis/redis.sock`, requires a Redis password, enables AOF persistence with `everysec` fsync, limits memory to `2048mb` by default, and uses the `allkeys-lru` eviction policy. The supplied test Hiera data overrides the password to `test-redis-password` and the memory limit to `256mb`. PuppetDB queries nodes declaring `Profile_redis_cluster`, but the returned node list is not used by any resource. A Linux-only `exec[None]` branch in the role remains unresolved and must be inspected before migration implementation.

## Service Type and Instances

**Service Type**: Redis in-memory data store/cache

**Configured Instances**:

- **default**: Default Redis daemon instance
  - Package: `redis-server` on Debian-family systems; verify the provider-specific package name on other operating systems
  - Service: `redis-server`
  - Service state: running and enabled
  - Bind address: `0.0.0.0`
  - Port: `6379`
  - Unix socket: `/var/run/redis/redis.sock`
  - Configuration: `/etc/redis/redis.conf`
  - Data directory: `/var/lib/redis`
  - Log directory: `/var/log/redis`
  - Service user/group: `redis` / `redis`
  - Authentication: `test-redis-password` with the supplied test Hiera override; otherwise `CHANGEME`
  - Maximum memory: `256mb` with the supplied test override; otherwise `2048mb`
  - Eviction policy: `allkeys-lru`
  - Persistence: AOF enabled
  - AOF fsync: `everysec`
  - Package management: enabled
  - Repository management: disabled
  - Configuration file mode: `0640`, owner `root`, group `redis`
  - Working directory mode: `0750`

## File Structure

**MANDATORY: Preserve this section from the original plan.**

```text
### Manifests

- site/role/manifests/redis_cluster.pp
- site/profile/manifests/cache/redis.pp
- modules/profile_redis_cluster/manifests/init.pp
- modules/profile_redis_cluster/manifests/install.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp
- modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp

### Custom components

- modules/profile_redis_cluster/lib/facter/redis_role.rb

### Templates

- redis/service_templates/redis.service.epp
- The Redis configuration template is selected by the dependency default redis/redis.conf.epp. Its source path was referenced by the manifest but is not present in the supplied directory listing.

### Data

- data/common.yaml
- data/environment/production.yaml
- data/environment/staging.yaml
- test/data/common.yaml
```

## Module Explanation

The module performs operations in the following order:

1. **`role::redis_cluster`** (`site/role/manifests/redis_cluster.pp`)
   - Includes `::profile::base::base`.
   - Includes `::profile::cache::redis`.
   - Orders the base profile before the Redis cache profile:
     `Class['::profile::base::base'] -> Class['::profile::cache::redis']`.
   - Reads `$facts['kernel']` to evaluate the Linux-only execution branch.
   - When `$facts['kernel'].downcase == 'linux'`, declares an `exec[None]` resource.
   - The command, execution path, refresh behavior, and idempotency conditions for `exec[None]` are unresolved in the supplied analysis.
   - Migration is incomplete until those execution details are inspected and mapped to an idempotent Ansible task.

2. **`profile::cache::redis`** (`site/profile/manifests/cache/redis.pp`)
   - Includes `profile_redis_cluster`.
   - Reads `fact('environment')`.
   - No direct package, file, or service resources are shown in the supplied execution tree.

3. **`profile_redis_cluster`** (`modules/profile_redis_cluster/manifests/init.pp`)
   - Defines the profile parameters:
     - `redis_port`: `6379`
     - `redis_password`: `CHANGEME`
     - `maxmemory_mb`: `2048`
     - `maxmemory_policy`: `allkeys-lru`
   - Queries PuppetDB for nodes declaring `Profile_redis_cluster`:
     `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`.
   - Assigns the returned certnames to `redis_nodes`.
   - Does not use `redis_nodes` in any subsequent resource.
   - Contains `profile_redis_cluster::install`.

4. **`profile_redis_cluster::install`** (`modules/profile_redis_cluster/manifests/install.pp`)
   - Declares the `redis` class with these profile overrides:
     - `bind`: `0.0.0.0`
     - `port`: `6379`
     - `requirepass`: `test-redis-password` with the supplied test Hiera data; otherwise `CHANGEME`
     - `maxmemory`: `256mb` with the supplied test Hiera data; otherwise `2048mb`
     - `maxmemory_policy`: `allkeys-lru`
     - `appendonly`: `true`
     - `appendfsync`: `everysec`
     - `manage_package`: `true`

5. **`redis`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`)
   - Inherits `redis::params`.
   - Contains `redis::preinstall`.
   - Contains `redis::install`.
   - Contains `redis::config`.
   - Contains `redis::service`.
   - Evaluates `$instances.each |$key, $values|`.
   - The resolved `$instances` value is `{}`, so the loop runs zero times and has no instance names to expand.
   - Orders:
     `Class['redis::preinstall'] -> Class['redis::install'] -> Class['redis::config']`.
   - Notifies the service when configuration changes:
     `Class['redis::config'] ~> Class['redis::service']`.
   - Effective values reported by the dependency/profile analysis include:
     - `bind`: `0.0.0.0`
     - `port`: `6379`
     - `requirepass`: `test-redis-password` in test; otherwise `CHANGEME`
     - `maxmemory`: `256mb` in test; otherwise `2048mb`
     - `maxmemory_policy`: `allkeys-lru`
     - `appendonly`: `true`
     - `appendfsync`: `everysec`
     - `manage_package`: `true`
     - `package_ensure`: `installed`
     - `default_install`: `true`
     - `manage_repo`: `false`
     - `service_manage`: `true`
     - `service_name`: normally `redis-server`; verify against the dependency platform parameters
     - `service_ensure`: `running`
     - `service_enable`: `true`
     - `service_user`: `redis`
     - `service_group`: `redis`
     - `config_dir`: `/etc/redis`
     - `config_file`: `/etc/redis/redis.conf`
     - `config_file_mode`: `0640`
     - `config_owner`: `root`
     - `config_group`: `redis`
     - `config_dir_mode`: dependency platform default; verify before migration
     - `config_file_orig`: dependency platform default; verify before migration
     - `log_dir`: `/var/log/redis`
     - `log_file`: `redis.log`
     - `log_dir_mode`: dependency platform default; verify before migration
     - `workdir`: `/var/lib/redis`
     - `workdir_mode`: `0750`
     - `pid_file`: dependency platform default, normally under `/var/run/redis`
     - `unixsocket`: `/var/run/redis/redis.sock`
     - `unixsocketperm`: `0755`
     - `ulimit`: `65536`
     - `ulimit_managed`: `true`
     - `managed_by_cluster_manager`: `false`
     - `cluster_enabled`: `false`
     - `instances`: `{}`
   - Values identified as dependency defaults or assumptions, including `manage_service_file`, `default_install`, `ulimit_managed`, `service_name`, and `instances`, must be verified against the dependency parameter definitions before implementation.

6. **`redis::preinstall`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`)
   - References `$facts['os']['name']` and `$facts['os']['family']`.
   - Repository management is disabled because `manage_repo` is `false`.
   - Does not create an `apt::ppa` resource.
   - Does not create `apt::source['redis']`.
   - If repository management is enabled in a future migration, implement the applicable OS-specific repository tasks.

7. **`redis::install`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`)
   - Manages package `redis-server` with ensure `installed` when the Debian-family package parameter resolves to the standard Redis package.
   - Creates the package resource because `manage_package` is `true`.
   - Skips DNF module management because `dnf_module_stream` is `undef`.
   - If `dnf_module_stream` is configured:
     - RedHat systems include `redis::dnfmodule` before installing Redis.
     - Non-RedHat systems fail explicitly.
   - Verify the package name on each target operating system before deployment.

8. **`redis::config`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`)
   - Applies Redis parameter defaults to managed file resources.
   - Creates `/etc/redis` as a directory with owner `root`, group `redis`, and dependency-defined directory mode.
   - Creates `/var/log/redis` as a directory with owner `redis`, group `redis`, and dependency-defined log directory mode.
   - Creates `/var/lib/redis` as a directory with owner `redis`, group `redis`, and mode `0750`.
   - With `default_install` enabled, declares `redis::instance['default']`.
   - With `ulimit_managed` enabled, contains `redis::ulimit`.
   - On Debian-family systems, creates `/etc/default/redis-server` as a file owned by `root:redis` with mode `0640`.
   - On non-Debian systems, does not create `/etc/default/redis-server`.
   - The values of `default_install` and `ulimit_managed` are dependency defaults that require verification.

9. **`redis::instance['default']`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`)
   - The explicit `default` instance is created even though the `$instances` loop runs zero times.
   - For title `default`, uses the dependency-defined `config_file_orig` as the source configuration path and `/etc/redis/redis.conf` as the active destination.
   - Manages the dependency source configuration file with owner `root`, group `redis`, mode `0640`.
   - Renders the dependency template `redis/redis.conf.epp` to the source configuration file.
   - Defines a refresh-only copy command:
     `cp -p [config_file_orig] /etc/redis/redis.conf`.
   - Uses path `/usr/bin:/bin`.
   - Subscribes the copy command to changes in the source configuration file.
   - Does not render `redis/service_templates/redis.service.epp` if `manage_service_file` is `false`; this value is a dependency default requiring verification.
   - The instance-level systemd drop-in is not created in the shown branch when no separate instance service file is managed.
   - The global ulimit class removes the obsolete drop-in.

10. **`redis::ulimit`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`)
    - With `managed_by_cluster_manager` set to `false`, does not create `/etc/security/limits.d/redis.conf`.
    - Ensures `/etc/systemd/system/redis-server.service.d/limit.conf` is absent.
    - The removal migrates away from the old managed service drop-in.

11. **`redis::service`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`)
    - Manages service `redis-server`.
    - Ensures the service is running.
    - Enables the service at boot.
    - Creates the resource because `service_manage` is `true`.
    - Receives notifications from `Class['redis::config']`.
    - The Ansible implementation must notify a Redis handler when the rendered or copied configuration changes.

12. **`redis::dnfmodule`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`)
    - Is not instantiated with the current `dnf_module_stream: undef` value.
    - If enabled, manages package `redis` with the configured stream, `enable_only: true`, and provider `dnfmodule`.

## Variables

**Variable Flow Summary**: Four profile variables are defined at the manifest level, two are overridden by test Hiera data, and no Redis-specific values are present in the supplied common or environment Hiera files. The migration should expose these values as Ansible variables, with the password stored securely.

### Variable Definitions

#### Manifest defaults

- `profile_redis_cluster::redis_port`: `6379` (type: integer)
- `profile_redis_cluster::redis_password`: `CHANGEME` (type: string; sensitive credential)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: integer)
- `profile_redis_cluster::maxmemory_policy`: `allkeys-lru` (type: string)

#### `test/data/common.yaml` → Migration note: Test overrides with higher priority than the manifest defaults

- `profile_redis_cluster::redis_password`: `test-redis-password` (type: string; sensitive credential)
- `profile_redis_cluster::maxmemory_mb`: `256` (type: integer)

#### `data/common.yaml` → Migration note: Common data for all nodes; no Redis-specific values

- Contains unrelated NTP, SSH, and syslog values.
- No Redis variables are defined.
- The exact unrelated key set was not included in the supplied exploration data.

#### `data/environment/production.yaml` → Migration note: Production environment data; no Redis-specific values

- `ntp::servers` (type: environment-specific NTP data)
- `syslog::server` (type: string)
- `syslog::facility` (type: string)
- No Redis variables are defined.

#### `data/environment/staging.yaml` → Migration note: Staging environment data; no Redis-specific values

- `syslog::server` (type: string)
- No Redis variables are defined.

### Hiera-to-Ansible Mapping

```yaml
redis_cluster_port: 6379
redis_cluster_password: "{{ vault_redis_cluster_password }}"
redis_cluster_maxmemory_mb: 256
redis_cluster_maxmemory_policy: allkeys-lru
redis_cluster_bind:
  - "0.0.0.0"
redis_cluster_appendonly: true
redis_cluster_appendfsync: everysec
redis_cluster_service_name: redis-server
redis_cluster_package_name: redis-server
```

The production/default value for `redis_cluster_maxmemory_mb` is `2048`; the test value is `256`. The test password must not be committed as plaintext and should be replaced by `vault_redis_cluster_password` in Ansible Vault or an external secret provider.

### Variable Migration Summary

- **Common defaults**: 4 profile variables defined in the manifest; no Redis variables in `data/common.yaml`
- **OS-specific variables**: 0 Redis variables supplied
- **Environment-specific variables**: 0 Redis variables supplied
- **Host-specific variables**: 0 Redis variables supplied
- **Test-specific overrides**: 2 variables from `test/data/common.yaml`
- **Encrypted variables**: 0 Hiera-eyaml values detected
- **Sensitive values requiring secure storage**: 1 configured Redis password; optional replication, Sentinel, and TLS secrets are supported by the dependency but are not configured

### Cross-Level Overrides

- **`profile_redis_cluster::redis_password`**
  - Defined at the manifest level as `CHANGEME`
  - Overridden by `test/data/common.yaml` as `test-redis-password`
  - Merge strategy: scalar first-value override; higher-priority test data wins

- **`profile_redis_cluster::maxmemory_mb`**
  - Defined at the manifest level as `2048`
  - Overridden by `test/data/common.yaml` as `256`
  - Merge strategy: scalar first-value override; higher-priority test data wins

### Merge Strategy Notes

- Variables using `hash` merge combine hash values from multiple levels using a shallow merge.
- Variables using `deep` merge recursively combine nested hash values.
- Variables using `first`, the default scalar behavior, use the first value found at the highest-priority Hiera level.
- The Redis profile variables shown here are scalar values and use first-value override behavior.

## Custom Types and Providers

### Custom fact: `redis_role`

- File: `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- Scope: Linux only
- Reads `/etc/redis/conf.d/replica.conf`.
- Returns `replica` when the file exists and contains the literal string `replicaof`.
- Returns `primary` otherwise.
- Takes no parameters.
- The fact is not referenced by the supplied execution tree.
- Ansible options:
  - Install a custom fact at `/etc/ansible/facts.d/redis_role.fact`, or
  - Use `stat` and `slurp`, then derive the value with `set_fact`.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib` `9.6.0`
- `puppet-redis` `11.0.0`
- `puppetlabs-apt` `9.4.0`

**System package dependencies**:

- `redis-server` on Debian-family systems
- `redis` when a RedHat DNF module stream is explicitly configured
- `systemd` for service management and ulimit/drop-in behavior
- Ansible Vault or an external secret provider for Redis credentials

**Service dependencies**:

- `profile::base::base` precedes `profile::cache::redis`.
- `redis::preinstall` precedes `redis::install`.
- `redis::install` precedes `redis::config`.
- `redis::config` notifies `redis::service`.
- The source Redis configuration file notifies the refresh-only copy operation.
- The copied active configuration should notify or restart `redis-server`.
- The unresolved Linux-only `exec[None]` resource must be analyzed before the role migration is complete.

## Puppet Facts Used

- `$facts['kernel']`
  - Determines whether the Linux-only `exec[None]` branch in `role::redis_cluster` is evaluated.

- `$facts['os']['name']`
  - Used by `redis::preinstall` for OS-specific repository behavior.

- `$facts['os']['family']`
  - Selects Debian repository behavior.
  - Rejects DNF module configuration on non-RedHat systems.
  - Controls creation of `/etc/default/redis-server` on Debian-family systems.

- `fact('environment')`
  - Read by `profile::cache::redis`.
  - No Redis resource behavior from this fact is shown.

- `redis_role`
  - Custom Linux fact described in the Custom Types and Providers section.
  - Not referenced by the supplied execution tree.

## Template Conversion Notes

### `redis/redis.conf.epp`

- Source: external `puppet-redis` dependency template.
- The file is referenced by the manifest but is not present in the supplied directory listing.
- Render count: reported as 1 for the `default` instance, but this count is unverified because the template node is absent from the supplied structured execution tree.
- Destination flow:
  - Render to the Puppet-managed source configuration path represented by `config_file_orig`.
  - Copy with `cp -p` to `/etc/redis/redis.conf`.
- Important resolved values:
  - `bind_arr`: `['0.0.0.0']`
  - `port`: `6379`
  - `requirepass`: `test-redis-password` in test; otherwise `CHANGEME`
  - `maxmemory`: `256mb` in test; otherwise `2048mb`
  - `maxmemory_policy`: `allkeys-lru`
  - `appendonly`: `true`
  - `appendfsync`: `everysec`
  - `cluster_enabled`: `false`
  - `tls_port`: `undef`
  - `replicaof`: `undef`
  - `slaveof`: `undef`
  - `masterauth`: `undef`
- The template supports deferred values through `inline_epp`; no concrete deferred values are supplied.
- Template parameters include:
  - `daemonize`
  - `pid_file`
  - `protected_mode`
  - `port`
  - `tcp_backlog`
  - `bind_arr`
  - `unixsocket`
  - `unixsocketperm`
  - `timeout`
  - `tcp_keepalive`
  - `log_level`
  - `log_file`
  - `syslog_enabled`
  - `syslog_facility`
  - `databases`
  - `save_db_to_disk`
  - `save_db_to_disk_interval`
  - `stop_writes_on_bgsave_error`
  - `rdbcompression`
  - `dbfilename`
  - `workdir`
  - `slaveof`
  - `replicaof`
  - `masterauth`
  - `slave_serve_stale_data`
  - `slave_read_only`
  - `repl_announce_ip`
  - `repl_announce_port`
  - `repl_ping_slave_period`
  - `repl_timeout`
  - `repl_disable_tcp_nodelay`
  - `repl_backlog_size`
  - `repl_backlog_ttl`
  - `slave_priority`
  - `min_slaves_to_write`
  - `min_slaves_max_lag`
  - `requirepass`
  - `rename_commands`
  - `maxclients`
  - `maxmemory`
  - `maxmemory_policy`
  - `maxmemory_samples`
  - `appendonly`
  - `appendfilename`
  - `appendfsync`
  - `no_appendfsync_on_rewrite`
  - `auto_aof_rewrite_percentage`
  - `auto_aof_rewrite_min_size`
  - `aof_load_truncated`
  - `slowlog_log_slower_than`
  - `slowlog_max_len`
  - `latency_monitor_threshold`
  - `notify_keyspace_events`
  - `hash_max_ziplist_entries`
  - `hash_max_ziplist_value`
  - `list_max_ziplist_entries`
  - `list_max_ziplist_value`
  - `set_max_intset_entries`
  - `zset_max_ziplist_entries`
  - `zset_max_ziplist_value`
  - `hll_sparse_max_bytes`
  - `activerehashing`
  - `output_buffer_limit_slave`
  - `output_buffer_limit_pubsub`
  - `hz`
  - `aof_rewrite_incremental_fsync`
  - `cluster_enabled`
  - `cluster_config_file`
  - `cluster_node_timeout`
  - `cluster_slave_validity_factor`
  - `cluster_require_full_coverage`
  - `cluster_migration_barrier`
  - `extra_config_file`
  - `tls_port`
  - `tls_cert_file`
  - `tls_key_file`
  - `tls_ca_cert_file`
  - `tls_ca_cert_dir`
  - `tls_ciphers`
  - `tls_ciphersuites`
  - `tls_protocols`
  - `tls_auth_clients`
  - `tls_replication`
  - `tls_cluster`
  - `tls_prefer_server_ciphers`
  - `modules`
  - `io_threads`
  - `io_threads_do_reads`
  - `cluster_allow_reads_when_down`
  - `cluster_replica_no_failover`
  - `dynamic_hz`
  - `activedefrag`
  - `active_defrag_ignore_bytes`
  - `active_defrag_threshold_lower`
  - `active_defrag_threshold_upper`
  - `active_defrag_cycle_min`
  - `active_defrag_cycle_max`
  - `active_defrag_max_scan_fields`
  - `jemalloc_bg_thread`
  - `rdb_save_incremental_fsync`
  - `acls`
  - `custom_options`

### `redis/service_templates/redis.service.epp`

- Render count: 0 for the current `default` instance if the dependency default `manage_service_file: false` is confirmed.
- The render count and `manage_service_file` value require verification against the dependency parameter definitions.
- If enabled, the template receives:
  - `bin_path`
  - `instance_title`
  - `port`
  - `redis_file_name`
  - `service_name`
  - `service_user`
  - `service_timeout_start`
  - `service_timeout_stop`
  - `ulimit`
  - `ulimit_managed`
- Contains one logic block.
- The normal Ansible implementation should use the distribution-provided `redis-server.service`; create a custom systemd unit only if dependency analysis confirms it is required.

## PuppetDB Dependencies

**Context**: PuppetDB is used for cross-node resource and infrastructure queries.

- **PuppetDB query**
  - Exact query: `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`
  - Location: `modules/profile_redis_cluster/manifests/init.pp`
  - Returned data: certnames of nodes declaring `Profile_redis_cluster`
  - Assigned variable: `redis_nodes`
  - Resource usage: no subsequent resource consumes `redis_nodes`
  - Migration: do not reproduce this query unless the deployment requires discovery of all Redis profile nodes. Use Ansible inventory groups, host variables, or service discovery if cluster membership is later required.

- **Exported resources**
  - None shown.

- **Resource collectors**
  - None shown.

- **Host identity data**
  - The query returns PuppetDB certnames, but those identities are not used for node classification or resource creation in the analyzed manifests.

## Credential and Secret Handling

- **Redis client password**
  - Test value: `test-redis-password`
  - Manifest default: `CHANGEME`
  - Rendered as the Redis `requirepass` setting.
  - Store as `vault_redis_cluster_password`.
  - Use `no_log: true` for tasks that may expose the credential.

- **Redis replication `masterauth`**
  - Optional dependency parameter.
  - Not configured by this profile.
  - Store in Vault if replication is enabled.

- **Sentinel authentication**
  - Supported by the dependency but not used in the supplied execution tree.
  - Store securely if introduced.

- **Redis TLS private key, certificate, and CA paths**
  - Not configured by this profile.
  - If added, deploy private keys with restrictive ownership and file modes.

- No Hiera-eyaml `ENC[PKCS7,...]` values were detected.
- No external secret provider was detected.

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
- `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- `data/common.yaml`
- `data/environment/production.yaml`
- `data/environment/staging.yaml`
- `test/data/common.yaml`
- External dependency template `redis/redis.conf.epp`, if available
- `redis/service_templates/redis.service.epp`

**Service endpoints to check**:

- `default`: TCP `0.0.0.0:6379`
- `default`: Unix socket `/var/run/redis/redis.sock`

**Templates rendered**:

- `default`: Redis configuration template, reported as 1 render but unverified because the external template node is absent from the supplied execution tree
- `default`: Redis systemd service template, reported as 0 renders if `manage_service_file: false` is confirmed

**Pre-flight checks**:

```bash
# Confirm the target operating system and package mapping.
. /etc/os-release
printf 'OS=%s\n' "$ID"
printf 'VERSION=%s\n' "$VERSION_ID"

# Confirm the package is available before installation.
apt-cache policy redis-server 2>/dev/null || true
dnf info redis 2>/dev/null || true

# Confirm the intended hierarchy and secret source.
test -n "${VAULT_REDIS_CLUSTER_PASSWORD:?Redis password must be supplied securely}"

# Verify the default instance directories.
install -d -m 0750 -o redis -g redis /var/lib/redis
install -d -o redis -g redis /var/log/redis
stat -c '%U:%G %a %n' /var/lib/redis /var/log/redis

# Verify the active default instance configuration.
test -f /etc/redis/redis.conf
grep -E '^[[:space:]]*bind[[:space:]]+0\.0\.0\.0' /etc/redis/redis.conf
grep -E '^[[:space:]]*port[[:space:]]+6379' /etc/redis/redis.conf
grep -E '^[[:space:]]*maxmemory-policy[[:space:]]+allkeys-lru' /etc/redis/redis.conf
grep -E '^[[:space:]]*appendonly[[:space:]]+yes' /etc/redis/redis.conf
grep -E '^[[:space:]]*appendfsync[[:space:]]+everysec' /etc/redis/redis.conf

# Verify the selected memory setting.
grep -E '^[[:space:]]*maxmemory[[:space:]]+(256mb|2048mb)' /etc/redis/redis.conf

# Validate Redis configuration using the distribution-appropriate method.
redis-server /etc/redis/redis.conf --test-memory 2>/dev/null || true

# Verify the obsolete ulimit drop-in is absent.
test ! -e /etc/systemd/system/redis-server.service.d/limit.conf

# Verify the default instance service.
systemctl is-enabled redis-server
systemctl is-active redis-server

# Verify the default instance TCP endpoint.
ss -lnt '( sport = :6379 )'

# Verify the default instance Unix socket.
test -S /var/run/redis/redis.sock

# Authenticate and test the default instance.
redis-cli -h 127.0.0.1 -p 6379 -a "$VAULT_REDIS_CLUSTER_PASSWORD" ping

# Verify the custom role fact if replica/primary classification is required.
facter redis_role 2>/dev/null || true
```

Before implementation is considered complete, inspect the Linux-only `exec[None]` branch in `site/role/manifests/redis_cluster.pp` and document its command, path, refresh conditions, and idempotency behavior.