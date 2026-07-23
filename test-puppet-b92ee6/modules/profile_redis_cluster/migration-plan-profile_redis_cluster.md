---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module configures a Redis cluster by installing Redis, setting up configuration files, and managing the Redis service. It uses the Redis module as a dependency and configures Redis with specific parameters for clustering, memory management, and authentication.

## Service Type and Instances

**Service Type**: In-memory Cache/Database (Redis)

**Configured Instances**:
- **Redis Server**: Redis cache server
  - Location/Path: /etc/redis
  - Port/Socket: 6379
  - Key Config: 2048MB max memory, allkeys-lru eviction policy, password authentication

## File Structure

- **Manifests**:
  - `modules/profile_redis_cluster/manifests/init.pp`
  - `modules/profile_redis_cluster/manifests/install.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`
  - `modules/profile_redis_cluster/migration-dependencies/redis/manifests/dnfmodule.pp`
  - `site/role/manifests/redis_cluster.pp`
  - `site/profile/manifests/cache/redis.pp`
- **Templates**:
  - `modules/profile_redis_cluster/migration-dependencies/redis/templates/redis.service.epp`
- **Facts**:
  - `modules/profile_redis_cluster/lib/facter/redis_role.rb`

## Module Explanation

The module performs operations in this order:

1. **role::redis_cluster** (`site/role/manifests/redis_cluster.pp`):
   - `exec 'None'` → if $facts['kernel'].downcase == 'linux', sets path to '/usr/bin:/bin:/usr/sbin:/sbin'
   - `include profile::base::base`
   - `contain profile::cache::redis`
   - Sets ordering: `profile::base::base -> profile::cache::redis`

2. **profile::cache::redis** (`site/profile/manifests/cache/redis.pp`):
   - Sets parameter: environment_name = fact('environment')
   - `class 'profile_redis_cluster'`

3. **profile_redis_cluster** (`modules/profile_redis_cluster/manifests/init.pp`):
   - Sets class parameters: redis_port=6379, redis_password='CHANGEME', maxmemory_mb=2048, maxmemory_policy='allkeys-lru'
   - `puppetdb_query` → queries for nodes with Class['Profile_redis_cluster']
   - `contain profile_redis_cluster::install`

4. **profile_redis_cluster::install** (`modules/profile_redis_cluster/manifests/install.pp`):
   - `class 'redis'` → bind: '0.0.0.0', port: 6379, requirepass: 'CHANGEME', maxmemory: '2048mb', appendonly: true, appendfsync: 'everysec', manage_package: true

5. **redis** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/init.pp`):
   - `inherits redis::params`
   - `contain redis::preinstall`
   - `contain redis::install`
   - `contain redis::config`
   - `contain redis::service`
   - Sets ordering: `redis::preinstall -> redis::install -> redis::config ~> redis::service`

6. **redis::preinstall** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/preinstall.pp`):
   - Conditional: if $redis::manage_repo (not set in our case)
   - Uses facts: $facts['os']['name'] and $facts['os']['family']

7. **redis::install** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/install.pp`):
   - Conditional: if $redis::manage_package (true)
     - `package 'redis-server'` → ensure: present
   - Conditional: if $redis::dnf_module_stream (not set in our case)

8. **redis::config** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/config.pp`):
   - `file '/etc/redis'` → ensure: directory
   - `file '/var/log/redis'` → ensure: directory
   - `file '/var/lib/redis'` → ensure: directory
   - Conditional: if $redis::default_install (true)
     - `redis::instance 'default'` → with many parameters including:
       - port: 6379
       - bind: '0.0.0.0'
       - requirepass: 'CHANGEME'
       - maxmemory: '2048mb'
       - maxmemory_policy: 'allkeys-lru'
       - appendonly: true
       - appendfsync: 'everysec'
       - Creates config file: `/etc/redis/redis.conf`
       - Creates systemd service file: `/etc/systemd/system/redis-server.service`
   - Conditional: if $redis::ulimit_managed (not explicitly set)
   - Conditional: case $facts['os']['family']

9. **redis::instance** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/instance.pp`):
   - For 'default' instance:
     - `file '/etc/redis/redis.conf.puppet'` → content: Redis configuration template
     - `file '/var/log/redis'` → if log_dir != $redis::log_dir
     - `file '/var/lib/redis'` → if workdir != $redis::workdir
     - `systemd::unit_file 'redis-server.service'` → if manage_service_file (true)
       - Template: 'redis/service_templates/redis.service.epp'
       - Variables: bin_path, instance_title, port, redis_file_name, service_name, service_user, service_timeout_start, service_timeout_stop, ulimit, ulimit_managed
     - `file '/etc/redis/redis.conf.puppet'` → Redis configuration
     - `exec 'copy /etc/redis/redis.conf.puppet to /etc/redis/redis.conf'` → refreshonly: true

10. **redis::service** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/service.pp`):
    - Conditional: if $redis::service_manage (not explicitly set, defaults to true)
      - `service 'redis-server'` → ensure: running, enable: true

11. **redis::ulimit** (`modules/profile_redis_cluster/migration-dependencies/redis/manifests/ulimit.pp`):
    - Not used in our case as $redis::ulimit_managed is not explicitly set

## Variables

**Variable Flow Summary**: 4 variables defined in profile_redis_cluster class

### Variable Definitions

**profile_redis_cluster class parameters**:
- `profile_redis_cluster::redis_port`: `6379` (type: Integer)
- `profile_redis_cluster::redis_password`: `'CHANGEME'` (type: String)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: Integer)
- `profile_redis_cluster::maxmemory_policy`: `'allkeys-lru'` (type: String)

### Variable Migration Summary

- **Common defaults**: 4 variables
- **OS-specific**: 0 variables
- **Environment-specific**: 0 variables
- **Host-specific**: 0 variables
- **Encrypted**: 1 variable (redis_password) needing secure storage

### Cross-Level Overrides

No cross-level overrides detected.

## Custom Types and Providers

**Custom Facts**:
- **redis_role**: Determines if a Redis instance is a primary or replica by checking if '/etc/redis/conf.d/replica.conf' exists and contains 'replicaof'.

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (version: 9.6.0)
- puppet-redis (version: 11.0.0)
- puppetlabs-apt (version: 9.4.0)

**System package dependencies**:
- redis-server

**Service dependencies**:
- profile::base::base must be applied before profile::cache::redis

## Puppet Facts Used

- `$facts['kernel']`: Determines if the system is Linux
- `$facts['os']['name']`: Used for OS-specific configurations
- `$facts['os']['family']`: Used for OS-specific configurations
- `$facts['environment']`: Used to determine the environment name

## Template Conversion Notes

**redis/service_templates/redis.service.epp**:
- Variables used: bin_path, instance_title, port, redis_file_name, service_name, service_user, service_timeout_start, service_timeout_stop, ulimit, ulimit_managed
- Contains 3 logic blocks for conditional configuration
- Creates systemd service unit file for Redis

## PuppetDB Dependencies

**PuppetDB Queries**:
- `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }` - Used to identify nodes with the Profile_redis_cluster class for clustering

## Checks for the Migration

**Files to verify**:
- `/etc/redis/redis.conf`
- `/etc/redis/redis.conf.puppet`
- `/etc/systemd/system/redis-server.service`
- `/var/log/redis`
- `/var/lib/redis`
- `/etc/redis`

**Service endpoints to check**:
- Redis server on port 6379

**Templates rendered**:
- redis.service.epp (1 instance)
- Redis configuration template (1 instance)

## Pre-flight checks:
```bash
# Service status commands
systemctl status redis-server

# Configuration validation commands
redis-cli -a <password> ping
redis-cli -a <password> info memory

# Check directory permissions
ls -la /etc/redis
ls -la /var/log/redis
ls -la /var/lib/redis

# Verify configuration file
grep -v "^#" /etc/redis/redis.conf | grep -v "^$"
```