---
source-path: modules/profile_redis_cluster
---

# Migration Plan: profile_redis_cluster

**TLDR**: This module manages Redis cluster nodes in a primary/replica architecture using PuppetDB for node discovery. It wraps the upstream Redis module, adding cluster-specific functionality including configuration management, role detection, and node communication.

## Service Type and Instances

**Service Type**: Redis (in-memory data structure store)

**Configured Instances**:
- **redis-server**: Primary Redis service
  - Location/Path: /var/lib/redis
  - Port/Socket: 6379
  - Key Config: Memory limits, password, persistence settings

## File Structure

```
profile_redis_cluster/
├── data/
│   ├── common.yaml
│   └── environment/
│       ├── production.yaml
│       └── staging.yaml
├── manifests/
│   ├── init.pp
│   └── install.pp
├── lib/
│   └── facter/
│       └── redis_role.rb
├── templates/
│   └── redis.conf.erb
└── metadata.json
```

## Module Explanation

The module performs operations in this order:

1. **role::redis_cluster** (not in this module):
   - Entry point class that includes profile::cache::redis
   - Sets up base system requirements before Redis

2. **profile::cache::redis** (not in this module):
   - Includes the profile_redis_cluster class
   - Depends on profile::base::base being applied first

3. **profile_redis_cluster** (`manifests/init.pp`):
   - Entry point for the Redis cluster profile
   - Sets parameters and includes the install class
   - Manages Redis configuration including memory limits, password, and persistence settings

4. **profile_redis_cluster::install** (`manifests/install.pp`):
   - Configures the Redis service using the upstream Redis module
   - Uses PuppetDB to discover other Redis nodes in the cluster
   - Sets up Redis instances with proper configuration

5. **redis::preinstall** (from Redis module):
   - Prepares the system for Redis installation
   - Creates required directories and users

6. **redis::install** (from Redis module):
   - Installs Redis packages
   - Manages repository configuration if required
   - Handles DNF module streams if specified

7. **redis::config** (from Redis module):
   - Configures Redis using the template
   - Creates configuration files for each instance
   - Sets up directories for config, logs, and data

8. **redis::service** (from Redis module):
   - Ensures Redis service is running and enabled
   - Manages service for each configured instance

9. **redis::ulimit** (from Redis module):
   - Configures system limits for Redis
   - Sets appropriate file descriptor limits

## Variables

**Variable Flow Summary**: Multiple variables across Hiera hierarchy levels

### Variable Definitions

**common.yaml (defaults)** → Migration note: Base defaults for all nodes
- `profile_redis_cluster::redis_port`: `6379` (type: integer)
- `profile_redis_cluster::redis_password`: `CHANGEME` (type: string)
- `profile_redis_cluster::maxmemory_mb`: `2048` (type: integer)
- `profile_redis_cluster::maxmemory_policy`: `allkeys-lru` (type: string)

**environment/production.yaml** → Migration note: Production-specific overrides
- `profile_redis_cluster::maxmemory_mb`: `4096` (type: integer)
- `profile_redis_cluster::redis_password`: `<encrypted>` (type: string)

**environment/staging.yaml** → Migration note: Staging-specific overrides
- `profile_redis_cluster::maxmemory_mb`: `1024` (type: integer)
- `profile_redis_cluster::redis_password`: `<encrypted>` (type: string)

### Variable Migration Summary

- **Common defaults**: 4 variables from common.yaml (base configuration for all nodes)
- **Environment-specific variables**: 2 variables that vary by deployment environment (staging, production)
- **Encrypted variables**: 1 variable (redis_password) that is encrypted and needs secure storage

### Cross-Level Overrides

Variables defined at multiple Hiera levels:
- **profile_redis_cluster::maxmemory_mb**: defined at common, production, staging levels, merge strategy: first
- **profile_redis_cluster::redis_password**: defined at common, production, staging levels, merge strategy: first

### Merge Strategy Notes

- Variables using `first` (default) - First value found wins, no merging

## Dependencies

**External module dependencies**:
- puppetlabs-stdlib (>= 9.0.0 < 10.0.0)
- puppet-redis (>= 11.0.0 < 12.0.0)

**System package dependencies**:
- redis-server

**Service dependencies**:
- PuppetDB (for node discovery)

## Puppet Facts Used

- `networking['fqdn']`: Used in the Redis configuration template to identify the node
- `kernel`: Used to check if the system is Linux
- `environment`: Used for environment-specific configuration
- `os['name']`: Used to determine OS-specific settings
- `os['family']`: Used to determine OS family for package management

## Template Conversion Notes

### redis.conf.erb

This template manages the Redis configuration file with the following key elements:
- Variables used: `@redis_port`, `@redis_password`, `@maxmemory_mb`, `@maxmemory_policy`
- Node identification using `@facts['networking']['fqdn']`
- Configuration sections for:
  - Network settings (bind address, port)
  - Security (password)
  - Persistence (appendonly, save rules)
  - Memory management (maxmemory, eviction policy)
  - Logging (logfile, loglevel)

## PuppetDB Dependencies

**Context**: PuppetDB provides a centralized data store for cross-node resource sharing, node facts, and infrastructure queries.

**Exported Resources**: None found in this module.

**Resource Collectors**: None found in this module.

**PuppetDB Queries**:
- Query: `resources[certname] { type = 'Class' and title = 'Profile_redis_cluster' }`
- Returned data: List of nodes with the Profile_redis_cluster class
- Migration notes: This query is used for Redis cluster node discovery. In a non-Puppet environment, this would need to be replaced with a service discovery mechanism or static configuration.

**Host Identity Data**: None found in this module.

## Checks for the Migration

**Files to verify**:
- /etc/redis/redis.conf
- /var/lib/redis
- /var/log/redis
- /etc/redis/conf.d

**Service endpoints to check**:
- TCP port 6379 (Redis)

**Templates rendered**:
- redis.conf.erb (1 instance)

## Pre-flight checks:
```bash
# Service status command
systemctl status redis-server

# Configuration validation
redis-cli -h localhost -p 6379 ping
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD ping

# Memory configuration check
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD INFO | grep maxmemory
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD INFO | grep maxmemory_policy

# Persistence configuration check
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET appendonly
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CONFIG GET appendfsync

# Cluster connectivity check
redis-cli -h localhost -p 6379 -a $REDIS_PASSWORD CLUSTER NODES
```