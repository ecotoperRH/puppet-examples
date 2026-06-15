---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module configures a Redis server as part of a Redis cluster. It sets up Redis with password authentication, memory limits, and persistence configuration. The module uses PuppetDB to query for other Redis cluster nodes and includes a custom fact to determine if a node is a primary or replica.

## Service Type and Instances

**Service Type**: Cache (Redis)

**Configured Instances**:
- **Redis Server**: In-memory data structure store
  - Location/Path: /var/lib/redis
  - Port/Socket: 6379 (configurable)
  - Key Config: Password authentication, memory limits, persistence settings

## File Structure

```
manifests/init.pp
manifests/install.pp
lib/facter/redis_role.rb
templates/redis.conf.erb
migration-dependencies/redis/manifests/init.pp
migration-dependencies/redis/manifests/preinstall.pp
migration-dependencies/redis/manifests/install.pp
migration-dependencies/redis/manifests/config.pp
migration-dependencies/redis/manifests/service.pp
migration-dependencies/redis/manifests/instance.pp
migration-dependencies/redis/manifests/ulimit.pp
migration-dependencies/redis/manifests/dnfmodule.pp
migration-dependencies/redis/templates/redis.conf.epp
migration-dependencies/redis/templates/service_templates/redis.service.epp
/workspace/source/site/role/manifests/redis_cluster.pp
/workspace/source/site/profile/manifests/cache/redis.pp
```

## Module Explanation

The module performs operations in this order:

1. **role::redis_cluster** (`/workspace/source/site/role/manifests/redis_cluster.pp`):
   - Includes profile::base::base class
   - Includes profile::cache::redis class
   - Sets ordering: Class['::profile::base::base'] -> Class['::profile::cache::redis']
   - Conditional: if $facts['kernel'] == 'Linux'
     - Creates Exec resource for Linux-specific operations
   - Resources: exec (1)

2. **profile::cache::redis** (`/workspace/source/site/profile/manifests/cache/redis.pp`):
   - Includes profile_redis_cluster class
   - Uses fact('environment') for environment-specific configuration
   - Resources: None (orchestration only)

3. **profile_redis_cluster** (`manifests/init.pp`):
   - Sets class parameters: redis_port=6379, redis_password='CHANGEME', maxmemory_mb=2048, maxmemory_policy='allkeys-lru'
   - Queries PuppetDB for all nodes with the Profile_redis_cluster class
   - Contains profile_redis_cluster::install class
   - Resources: None (orchestration only)

4. **profile_redis_cluster::install** (`manifests/install.pp`):
   - Includes redis class with parameters:
     - bind='0.0.0.0'
     - port=$profile_redis_cluster::redis_port (6379)
     - requirepass=$profile_redis_cluster::redis_password ('CHANGEME')
     - maxmemory="${profile_redis_cluster::maxmemory_mb}mb" (2048mb)
     - appendonly=true
     - appendfsync='everysec'
     - manage_package=true
   - Resources: None (orchestration only)

5. **redis** (`migration-dependencies/redis/manifests/init.pp`):
   - Includes redis::preinstall class
   - Includes redis::install class
   - Includes redis::config class
   - Includes redis::service class
   - Sets ordering: redis::preinstall -> redis::install -> redis::config ~> redis::service
   - For each instance in $instances hash:
     - Creates redis::instance[default] resource
   - Resources: None (orchestration only)

6. **redis::preinstall** (`migration-dependencies/redis/manifests/preinstall.pp`):
   - Conditional: if $redis::manage_repo
     - Checks OS family and name to determine repository configuration
   - Resources: None (no repository management in this case)

7. **redis::install** (`migration-dependencies/redis/manifests/install.pp`):
   - Conditional: if $redis::manage_package
     - Installs package: redis-server
   - Conditional: if $redis::dnf_module_stream
     - Includes redis::dnfmodule class
       - **redis::dnfmodule** (`migration-dependencies/redis/manifests/dnfmodule.pp`):
         - Installs package: redis dnf module
         - Resources: package (1)
   - Resources: package (1)

8. **redis::config** (`migration-dependencies/redis/manifests/config.pp`):
   - Creates directory: $redis::config_dir (/etc/redis)
     - owner: redis
     - group: redis
     - mode: 0755
   - Creates directory: $redis::log_dir (/var/log/redis)
     - owner: redis
     - group: redis
     - mode: 0755
   - Creates directory: $redis::workdir (/var/lib/redis)
     - owner: redis
     - group: redis
     - mode: 0755
   - Conditional: if $redis::default_install
     - Creates redis::instance[default]
       - Deploys configuration file:
         - Template: redis.conf.epp → /etc/redis/redis.conf (mode: 0644)
         - Sets: bind='0.0.0.0', port=6379, requirepass='CHANGEME', maxmemory='2048mb', appendonly=true, appendfsync='everysec'
   - Conditional: if $redis::ulimit_managed
     - Includes redis::ulimit class
       - **redis::ulimit** (`migration-dependencies/redis/manifests/ulimit.pp`):
         - Conditional: if $redis::managed_by_cluster_manager
           - Creates file: /etc/security/limits.d/redis.conf
             - owner: root
             - group: root
             - mode: 0644
             - content: Redis ulimit settings
         - Creates file: /etc/systemd/system/${redis::service_name}.service.d/limit.conf
           - owner: root
           - group: root
           - mode: 0644
           - content: Redis systemd service limits
         - Resources: file (2)
   - Conditional: case $facts['os']['family']
     - Creates file: /etc/default/redis-server
       - owner: root
       - group: root
       - mode: 0644
       - content: Redis server defaults
   - Resources: file (4), redis::instance (1)
   - **notifies**: file[/etc/redis/redis.conf] ~> service[redis-server]

9. **redis::service** (`migration-dependencies/redis/manifests/service.pp`):
   - Conditional: if $redis::service_manage
     - Manages service: redis-server
       - ensure: running
       - enable: true
       - hasrestart: true
       - hasstatus: true
   - Resources: service (1)

10. **redis::instance** (`migration-dependencies/redis/manifests/instance.pp`):
    - Creates Redis instance configuration
    - Manages configuration files and service for the instance
    - Resources: file (1), service (1)

## Variables

**Variable Flow Summary**: 4 variables in profile_redis_cluster module

### Variable Definitions

**common.yaml (defaults)** → Migration note: Base defaults for all nodes
- No Redis-specific variables defined in common.yaml

**environment/production.yaml (environment overrides)** → Migration note: Environment-specific variables, loaded based on deployment environment
- No Redis-specific variables defined in production.yaml

**environment/staging.yaml (environment overrides)** → Migration note: Environment-specific variables, loaded based on deployment environment
- No Redis-specific variables defined in staging.yaml

**profile_redis_cluster class parameters** → Migration note: Default values defined in the class
- `profile_redis_cluster::redis_port`: `6379` (type: integer)
- `profile_redis_cluster::redis_password`: `'CHANGEME'` (type: string)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: integer)
- `profile_redis_cluster::maxmemory_policy`: `'allkeys-lru'` (type: string)

### Variable Migration Summary

- **Module parameters**: 4 variables defined in the profile_redis_cluster class
- **Encrypted variables**: 1 variable (redis_password) that needs secure storage

### Cross-Level Overrides

No cross-level overrides detected for Redis variables.

### Merge Strategy Notes

No merge strategies detected for Redis variables.

## Custom Types and Providers

### Custom Fact: redis_role
- **Name**: redis_role
- **Purpose**: Determines if a Redis instance is configured as a primary or replica node
- **Implementation**: Checks for the presence of 'replicaof' directive in /etc/redis/conf.d/replica.conf
- **Platform constraints**: Linux only (confine kernel: 'Linux')
- **Return values**: 'primary' or 'replica'
- **Migration notes**: This fact should be replaced with an Ansible fact that performs the same check on the Redis configuration file to determine the node role.

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (forge, version: 9.6.0)
- puppet-redis (forge, version: 11.0.0)
- puppetlabs-apt (forge, version: 9.4.0)

**System package dependencies**:
- redis-server

**Service dependencies**:
- None explicit, but Redis service depends on configuration files

### Dependency Details

- **puppetlabs-stdlib**: Standard library functions, version 9.6.0
  - Source: forge
  - Used for: Common Puppet functions and types

- **puppet-redis**: Redis module, version 11.0.0
  - Source: forge
  - Used for: Installing and configuring Redis server

- **puppetlabs-apt**: APT package management, version 9.4.0
  - Source: forge
  - Used for: Managing APT repositories on Debian-based systems

## Puppet Facts Used

- `$facts['kernel']` - Operating system kernel (Linux, Windows, etc.)
- `$facts['os']['family']` - Operating system family (RedHat, Debian, etc.)
- `$facts['os']['name']` - Operating system name
- `$facts['networking']['fqdn']` - Fully qualified domain name
- `fact('environment')` - Current Puppet environment

## Template Conversion Notes

### redis.conf.erb
- **Variables used**:
  - `@facts['networking']['fqdn']` - Node's fully qualified domain name
  - `@redis_port` - Redis server port
  - `@redis_password` - Redis authentication password
  - `@maxmemory_mb` - Maximum memory in MB
  - `@maxmemory_policy` - Memory eviction policy
- **Ruby logic blocks**: None, simple variable substitution only
- **Conditional rendering**: None
- **Iterations**: None
- **Complex expressions**: None

## PuppetDB Dependencies

### PuppetDB Queries (`puppetdb_query()`)
- **Query**: `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`
- **Returns**: List of nodes with the Profile_redis_cluster class
- **Used for**: Identifying all Redis cluster nodes
- **Migration notes**: This query retrieves all Redis cluster nodes. In Ansible, this would be replaced with inventory groups or dynamic inventory to identify Redis cluster members.

## Checks for the Migration

**Files to verify**:
- /etc/redis/redis.conf
- /etc/default/redis-server
- /etc/systemd/system/redis-server.service.d/limit.conf
- /etc/security/limits.d/redis.conf

**Service endpoints to check**:
- TCP port 6379 (Redis)

**Templates rendered**:
- redis.conf.erb → /etc/redis/redis.conf (1 instance)

## Pre-flight checks:
```bash
# Service status command
systemctl status redis-server

# Redis connectivity check
redis-cli -a <password> ping

# Redis configuration test
redis-server --test-memory <maxmemory_mb>
```