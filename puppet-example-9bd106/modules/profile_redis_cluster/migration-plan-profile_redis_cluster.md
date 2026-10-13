---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module applies a Linux Redis profile through `role::redis_cluster → profile::base::base → profile::cache::redis → profile_redis_cluster`. The visible execution path installs and manages the default Redis instance on port `6379`, creates Redis-related directories, and configures the Redis service. The supplied validation confirms the class relationships, base-profile conditionals, Redis dependency ordering, default-instance creation, and empty `instances` loop. Hiera values, dependency versions, detailed resource attributes, custom-fact behavior, PuppetDB usage, and Redis configuration-template contents were not present in the validated structured analysis and must be verified before migration.

## Service Type and Instances

**Service Type**: In-memory database/cache — Redis server.

**Configured Instances**:

- **default**: Implicit default Redis instance created when `default_install == true`.
  - Location/Path: Redis configuration under `/etc/redis` or `/etc/redis.conf` on older RedHat systems; data under `/var/lib/redis`; logs under `/var/log/redis`
  - Port/Socket: TCP `6379`; Unix socket `/var/run/redis/redis.sock`
  - Key Config: Redis service is managed by the dependency module; the supplied plan specifies bind address `0.0.0.0`, AOF persistence, `everysec` fsync, `allkeys-lru` memory policy, and authentication values, but detailed effective attributes were not confirmed by the structured validation
  - Debian-family service: `redis-server`
  - RedHat-family service: `redis`
  - Debian-family configuration: `/etc/redis/redis.conf`
  - RedHat 9+ configuration: `/etc/redis/redis.conf`
  - RedHat versions before 9 configuration: `/etc/redis.conf`
  - Debian-family and RedHat 9+ generated source: `/etc/redis/redis.conf.puppet`
  - RedHat versions before 9 generated source: `/etc/redis.conf.puppet`
  - Debian-family PID file: `/var/run/redis/redis-server.pid`
  - RedHat-family PID file: `/var/run/redis_6379.pid`
  - Log file: `/var/log/redis/redis.log`
  - Service state and enablement: Declared as `running` and enabled in the supplied plan; verify from dependency defaults during implementation

No additional named instances are configured. The `instances` hash resolves to `{}` in the supplied plan, so its loop executes zero times.

## File Structure

**MANDATORY: Preserve this section from the original plan.**

### Manifests in the execution tree

- `site/role/manifests/redis_cluster.pp`
- `site/profile/manifests/base/base.pp`
- `site/profile/manifests/cache/redis.pp`
- `site/modules/linux/profile_redis_cluster/manifests/init.pp`
- `site/modules/linux/profile_redis_cluster/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`

### Referenced data files

- `test/data/common.yaml`
- `data/common.yaml`
- `data/environment/production.yaml`
- `data/environment/staging.yaml`

### Referenced template

- `redis/service_templates/redis.service.epp`

The supplied plan also names `redis/redis.conf.epp`, but that file is not present in the supplied directory listing and was not identified by the validated structured analysis.

### Custom components

- `modules/profile_redis_cluster/lib/facter/redis_role.rb`

## Module Explanation

The module performs operations in this order:

1. **`role::redis_cluster`** (`site/role/manifests/redis_cluster.pp`):
   - Applies the role conditionally when `$facts['kernel'].downcase == 'linux'`.
   - Sets the default `Exec` path to `/usr/bin:/bin:/usr/sbin:/sbin`.
   - Includes `::profile::base::base`.
   - Contains `::profile::cache::redis`.
   - Orders `Class['::profile::base::base']` before `Class['::profile::cache::redis']`.
   - The reported `exec[None]` represents an `Exec` default declaration; no concrete command resource is shown.

2. **`profile::base::base`** (`site/profile/manifests/base/base.pp`):
   - Uses the supplied default values `manage_ntp == true`, `manage_syslog == true`, and `manage_utils == true`; Hiera support for these values was not confirmed in structured validation.
   - Includes `base_utils` when `manage_utils == true`.
   - When `manage_ntp == true` and the kernel is Linux:
     - Installs package `chrony`.
     - Manages service `chronyd` as enabled and running.
   - When `manage_syslog == true` and the kernel is Linux:
     - Installs package `rsyslog`.
     - Manages service `rsyslog` as enabled and running.
   - `base_utils` is external to the supplied execution tree.

3. **`profile::cache::redis`** (`site/profile/manifests/cache/redis.pp`):
   - Sets `environment_name` from `fact('environment')`.
   - Includes `profile_redis_cluster`.
   - No validated evidence shows that `environment_name` changes Redis resources.

4. **`profile_redis_cluster`** (`site/modules/linux/profile_redis_cluster/manifests/init.pp`):
   - Declares the profile parameters used by the Redis installation class.
   - Contains `profile_redis_cluster::install`.
   - The supplied validation confirms the containment relationship.
   - A PuppetDB query is described in the unvalidated plan text, but it is absent from the validated structured execution tree and is therefore excluded from the migration design.

5. **`profile_redis_cluster::install`** (`site/modules/linux/profile_redis_cluster/manifests/install.pp`):
   - Declares the dependency module’s `redis` class.
   - The supplied plan specifies bind address `0.0.0.0`, port `6379`, Redis authentication, memory settings, AOF persistence, and package management.
   - Manages `/var/log/redis` as a directory owned by `redis:redis` with mode `0755`; these detailed attributes require verification against the source manifest.

6. **`redis`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`):
   - Inherits `redis::params`.
   - Contains `redis::preinstall`, `redis::install`, `redis::config`, and `redis::service`.
   - Orders `redis::preinstall` before `redis::install`, and `redis::install` before `redis::config`.
   - The `instances.each` loop executes zero times because `instances` is `{}`.
   - The implicit default instance is created by `redis::config` when `default_install == true`.
   - When `notify_service == true`, configuration refreshes the Redis service.

7. **`redis::preinstall`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`):
   - Handles repository configuration when `manage_repo == true`.
   - The supplied plan states that the effective value is `false`, so no repository resource is created.
   - Ubuntu PPA and Debian Redis repository branches are not executed under the stated configuration.

8. **`redis::install`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`):
   - Installs the Redis package when `manage_package == true`.
   - The supplied plan identifies `redis-server` for Debian-family systems and `redis` for RedHat-family systems.
   - FreeBSD, Suse, and Archlinux are reported to use package name `redis`.
   - DNF module handling is delegated to `redis::dnfmodule` only when a DNF module stream is supplied.
   - Package names and effective platform branches must be verified against the dependency module before migration.

9. **`redis::config`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`):
   - Creates platform-specific Redis configuration, log, and data directories.
   - Creates `/etc/default/redis-server` on Debian-family systems according to the supplied plan.
   - Does not create `/etc/default/redis-server` on RedHat-family systems.
   - Creates `redis::instance 'default'` when `default_install == true`.
   - Contains `redis::ulimit` when `ulimit_managed == true`.
   - The detailed ownership and mode values in the supplied plan require source verification.

10. **`redis::instance 'default'`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`):
    - Renders the default Redis configuration to a Puppet-generated source file.
    - Uses the platform-specific active configuration path.
    - Manages the default instance on port `6379`.
    - Uses the platform-specific service name and PID file.
    - Uses `/var/run/redis/redis.sock` as the Unix socket according to the supplied plan.
    - Copies the generated source configuration to the active configuration path with a refresh-only `exec`.
    - The generated service template is not used when `manage_service_file == false`; the effective value and render count were not confirmed by structured validation.
    - No additional instance names are expanded because `instances` is empty.

11. **`redis::ulimit`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`):
    - Handles Redis process limits when enabled.
    - The supplied plan states that `managed_by_cluster_manager == false`, so `/etc/security/limits.d/redis.conf` is not created.
    - Removes the managed systemd limit drop-in when applicable:
      - Debian-family: `/etc/systemd/system/redis-server.service.d/limit.conf`
      - RedHat-family: `/etc/systemd/system/redis.service.d/limit.conf`
    - The effective limit values require verification against the dependency defaults.

12. **`redis::service`** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`):
    - Manages the Redis service when `service_manage == true`.
    - Debian-family service: `redis-server`.
    - RedHat-family service: `redis`.
    - Configuration changes notify the service.
    - The supplied plan declares the service enabled and running; verify these effective values before migration.

## Variables

**Variable Flow Summary**: The supplied plan identifies profile defaults and test Hiera overrides, but the validated structured analysis does not contain the Hiera file contents or hierarchy resolution. Values below are therefore classified as reported or unverified rather than independently validated.

### Variable Definitions

#### `test/data/common.yaml` — test hierarchy

Reported values:

- `profile_redis_cluster::redis_password`: `test-redis-password` (type: string; Hiera value not independently validated)
- `profile_redis_cluster::maxmemory_mb`: `256` (type: integer; Hiera value not independently validated)

#### `data/common.yaml` — common defaults

- No Redis-specific variables were reported.
- No `profile_redis_cluster::*` variables were reported.
- No `redis::*` variables were reported.
- File contents were not present in the validated structured analysis.

#### `data/environment/production.yaml` — production hierarchy

- No Redis-specific variables were reported.
- No `profile_redis_cluster::*` variables were reported.
- No `redis::*` variables were reported.
- File contents were not present in the validated structured analysis.

#### `data/environment/staging.yaml` — staging hierarchy

- No Redis-specific variables were reported.
- No `profile_redis_cluster::*` variables were reported.
- No `redis::*` variables were reported.
- File contents were not present in the validated structured analysis.

### Reported Effective Profile Values

#### Production and staging

- `profile_redis_cluster::redis_port`: `6379` (type: integer; reported default)
- `profile_redis_cluster::redis_password`: `CHANGEME` (type: string; reported default)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: integer; reported default)
- `profile_redis_cluster::maxmemory_policy`: `allkeys-lru` (type: string; reported default)

#### Test

- `profile_redis_cluster::redis_port`: `6379` (type: integer; reported default)
- `profile_redis_cluster::redis_password`: `test-redis-password` (type: string; reported Hiera override)
- `profile_redis_cluster::maxmemory_mb`: `256` (type: integer; reported Hiera override)
- `profile_redis_cluster::maxmemory_policy`: `allkeys-lru` (type: string; reported default)

### Variable Migration Summary

- **Common defaults**: Four reported profile defaults; common Hiera file contents are unverified.
- **OS-specific variables**: None identified in the supplied plan.
- **Environment-specific variables**: No production or staging Redis-specific values reported.
- **Test variables**: Two reported overrides.
- **Host-specific variables**: None identified.
- **Encrypted variables**: None identified.
- **Sensitive values**: One concrete Redis password value requires secure migration.
- **TLS values**: Optional parameters are mentioned but no concrete TLS values are supplied.

### Ansible Mapping

- `profile_redis_cluster::redis_port` → `redis_cluster_port`
- `profile_redis_cluster::redis_password` → `redis_cluster_password`
- `profile_redis_cluster::maxmemory_mb` → `redis_cluster_maxmemory_mb`
- `profile_redis_cluster::maxmemory_policy` → `redis_cluster_maxmemory_policy`

### Cross-Level Overrides

Variables reported at multiple levels:

- `profile_redis_cluster::redis_password`: Puppet class default and test Hiera; reported merge behavior is first/highest-priority value.
- `profile_redis_cluster::maxmemory_mb`: Puppet class default and test Hiera; reported merge behavior is first/highest-priority value.
- No hash or deep merge was identified for the Redis profile values.

### Merge Strategy Notes

- Variables using `hash` merge: None identified.
- Variables using `deep` merge: None identified.
- Variables using `first` or default lookup: Scalar profile values, including the password and maximum memory, use first/highest-priority lookup behavior as reported.
- Hiera hierarchy and exact precedence require verification from the actual data source.

## Custom Types and Providers

### Custom fact reported in the source plan

- File: `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- The file is listed in the supplied directory structure.
- Its implementation and behavior were not present in the validated structured analysis.
- Do not reproduce its reported `primary`/`replica` behavior in the migration until the file is reviewed.
- No custom resource type or provider was confirmed.

## Dependencies

**External module dependencies**:

- `puppetlabs-stdlib`
- `puppet-redis`
- `puppetlabs-apt`

Exact versions stated in the supplied plan were not supported by the validated dependency analysis and must be confirmed from `Puppetfile` or `metadata.json`.

**System package dependencies**:

- `chrony`
- `rsyslog`
- Debian-family Redis package: reported as `redis-server`
- RedHat-family Redis package: reported as `redis`
- Other supported platforms: reported as `redis`

Package names and platform support require verification against the dependency module.

**Service dependencies**:

- `Class['::profile::base::base']` precedes `Class['::profile::cache::redis']`.
- `redis::preinstall` precedes `redis::install`.
- `redis::install` precedes `redis::config`.
- `redis::config` refreshes `redis::service`.
- The generated Redis source configuration refreshes the refresh-only copy command.
- Repository management is reported as disabled.
- `base_utils` is included when `manage_utils == true`, but its implementation is outside the supplied execution tree.

## Puppet Facts Used

- `$facts['kernel']`
  - Selects Linux-specific role behavior.
  - Controls the base-profile NTP and syslog conditionals.
- `$facts['os']['name']`
  - Reported as being used for platform-specific repository handling; verify in the source manifest.
- `$facts['os']['family']`
  - Reported as being used for package, path, ownership, and service selection; verify in the source manifest.
- `$facts['os']['release']['major']`
  - Reported as being used to distinguish RedHat 9+ from earlier RedHat releases; verify in the source manifest.
- `fact('environment')`
  - Passed to `profile::cache::redis::environment_name`.
  - No validated evidence shows that it changes Redis resources.
- `redis_role`
  - The file is listed as a custom fact, but its behavior and use were not confirmed by structured validation.

## Template Conversion Notes

### `redis/service_templates/redis.service.epp`

- The template is listed in the supplied file structure.
- It is conditionally used by `redis::instance`.
- The effective value of `manage_service_file` and the render count were not confirmed by structured validation.
- Do not assume zero renders until the effective parameter resolution is verified.
- The supplied plan reports parameters including instance name, port, configuration path, service name, service user, timeout values, and ulimit settings; these parameters require template and manifest review.

### Redis configuration template

- The supplied plan names `redis/redis.conf.epp`.
- This template is absent from the supplied directory listing and was not identified in the validated structured analysis.
- Its variables, Ruby/EPP logic, destination, and render count cannot be confirmed.
- Remove any migration implementation that depends on its detailed parameter list until the template is located and reviewed.

## Checks for the Migration

**Files to verify**:

- `site/role/manifests/redis_cluster.pp`
- `site/profile/manifests/base/base.pp`
- `site/profile/manifests/cache/redis.pp`
- `site/modules/linux/profile_redis_cluster/manifests/init.pp`
- `site/modules/linux/profile_redis_cluster/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`
- `modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`
- `modules/profile_redis_cluster/lib/facter/redis_role.rb`
- `test/data/common.yaml`
- `data/common.yaml`
- `data/environment/production.yaml`
- `data/environment/staging.yaml`
- `redis/service_templates/redis.service.epp`
- `redis/redis.conf.epp`, if present outside the supplied listing
- `Puppetfile`
- `metadata.json`

**Service endpoints to check**:

- **default**: TCP `6379`
- **default**: Unix socket `/var/run/redis/redis.sock`

**Templates rendered**:

- **default Redis configuration**: Render count unverified because `redis/redis.conf.epp` was not available in validated analysis.
- **default systemd service template**: Render count unverified because `manage_service_file` was not resolved in validated analysis.

## Pre-flight checks

```bash
# Confirm the target operating system and release.
facter os
facter kernel

# Confirm package availability and install the platform-appropriate package.
# Debian-family:
apt-cache policy redis-server
# RedHat-family:
dnf info redis

# Confirm Redis service identity after installation.
getent passwd redis
getent group redis

# Confirm the default instance directories.
stat /var/lib/redis
stat /var/log/redis
stat /etc/redis

# Confirm the active service name for the target platform.
systemctl list-unit-files | grep -E '^(redis-server|redis)\.service'

# Confirm the default instance is enabled and running.
systemctl is-enabled redis-server || systemctl is-enabled redis
systemctl is-active redis-server || systemctl is-active redis

# Confirm the active configuration path.
test -f /etc/redis/redis.conf || test -f /etc/redis.conf

# Confirm the generated source configuration path.
test -f /etc/redis/redis.conf.puppet || test -f /etc/redis.conf.puppet

# Validate Redis configuration using the platform-supported command.
redis-server --test-memory 2

# Check the default instance endpoint.
redis-cli -p 6379 -a '<vault-managed-password>' ping

# Expected response:
# PONG

# Check the Unix socket.
redis-cli -s /var/run/redis/redis.sock -a '<vault-managed-password>' ping

# Verify the configuration values after the template and Hiera sources
# have been independently confirmed.
grep -E '^(bind|port|appendonly|appendfsync|maxmemory|maxmemory-policy|requirepass)' \
  /etc/redis/redis.conf /etc/redis.conf 2>/dev/null

# Confirm obsolete systemd limit drop-ins are absent where applicable.
test ! -e /etc/systemd/system/redis-server.service.d/limit.conf
test ! -e /etc/systemd/system/redis.service.d/limit.conf

# Verify the Redis password is supplied through Ansible Vault or another
# secret manager and is not exposed in logs.
```

### Credentials and Sensitive Values

- `profile_redis_cluster::redis_password`
  - Reported production default: `CHANGEME`
  - Reported test value: `test-redis-password`
  - The values were not confirmed by the validated Hiera analysis.
  - Store the migrated value in Ansible Vault or an external secret manager.
  - Use `no_log: true` for tasks that handle the password.
  - Render Redis configuration with restrictive permissions, preferably `0640` or stricter.
- Optional sensitive parameters reported by the source plan:
  - `masterauth`
  - `requirepass`
  - `tls_cert_file`
  - `tls_key_file`
  - `tls_ca_cert_file`
- No concrete Sentinel or TLS values were confirmed.